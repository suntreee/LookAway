import AppKit

enum EyePhase: String {
    case work
    case rest
}

enum TimeDisplayMode: String {
    case full
    case compact
}

enum ReminderStyle: String {
    case softCard
    case dimScreen
}

struct Settings {
    var workSeconds: Int
    var restSeconds: Int
    var rhythmName: String
    var isCustomRhythm: Bool
    var timeDisplayMode: TimeDisplayMode
    var reminderStyle: ReminderStyle

    static let defaults = UserDefaults.standard

    static func load() -> Settings {
        let hasNewSavedValues = defaults.object(forKey: "workSeconds") != nil
        let hasLegacySavedValues = defaults.object(forKey: "workMinutes") != nil
        let savedWorkSeconds = hasNewSavedValues ? defaults.integer(forKey: "workSeconds") : defaults.integer(forKey: "workMinutes") * 60
        let savedReminderStyle = defaults.string(forKey: "reminderStyle") ?? ""
        let reminderStyle = savedReminderStyle == "breathingBorder" ? ReminderStyle.dimScreen : (ReminderStyle(rawValue: savedReminderStyle) ?? .softCard)
        return Settings(
            workSeconds: (hasNewSavedValues || hasLegacySavedValues) ? max(1, savedWorkSeconds) : 20 * 60,
            restSeconds: (hasNewSavedValues || hasLegacySavedValues) ? max(1, defaults.integer(forKey: "restSeconds")) : 20,
            rhythmName: defaults.string(forKey: "rhythmName") ?? "20-20-20",
            isCustomRhythm: defaults.bool(forKey: "isCustomRhythm"),
            timeDisplayMode: TimeDisplayMode(rawValue: defaults.string(forKey: "timeDisplayMode") ?? "") ?? .full,
            reminderStyle: reminderStyle
        )
    }

    func save() {
        Settings.defaults.set(workSeconds, forKey: "workSeconds")
        Settings.defaults.set(restSeconds, forKey: "restSeconds")
        Settings.defaults.set(rhythmName, forKey: "rhythmName")
        Settings.defaults.set(isCustomRhythm, forKey: "isCustomRhythm")
        Settings.defaults.set(timeDisplayMode.rawValue, forKey: "timeDisplayMode")
        Settings.defaults.set(reminderStyle.rawValue, forKey: "reminderStyle")
    }
}

final class DailyStats {
    private let defaults = UserDefaults.standard
    private let dateKey = "statsDate"
    private let workKey = "statsWorkSeconds"
    private let restKey = "statsRestSeconds"

    var workSeconds: Int {
        rollIfNeeded()
        return defaults.integer(forKey: workKey)
    }

    var restSeconds: Int {
        rollIfNeeded()
        return defaults.integer(forKey: restKey)
    }

    func record(_ phase: EyePhase) {
        rollIfNeeded()
        let key = phase == .work ? workKey : restKey
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    private func rollIfNeeded() {
        let today = Self.todayString()
        if defaults.string(forKey: dateKey) != today {
            defaults.set(today, forKey: dateKey)
            defaults.set(0, forKey: workKey)
            defaults.set(0, forKey: restKey)
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

enum LaunchAtLoginManager {
    private static let identifier = "local.lookaway.menubar.login"

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(identifier).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default
        let directory = launchAgentURL.deletingLastPathComponent()

        if enabled {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": identifier,
                "ProgramArguments": [
                    "/usr/bin/open",
                    Bundle.main.bundlePath
                ],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } else if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }
    }
}

final class TimerModel {
    var settings = Settings.load()
    let stats = DailyStats()
    var phase: EyePhase = .work
    var isRunning = true
    var remainingSeconds: Int
    var totalSeconds: Int
    var onChange: (() -> Void)?
    var onRestStarted: (() -> Void)?
    private var timer: Timer?

    init() {
        remainingSeconds = max(1, settings.workSeconds)
        totalSeconds = remainingSeconds
    }

    func start() {
        isRunning = true
        scheduleTimer()
        onChange?()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        onChange?()
    }

    func resetToWork() {
        phase = .work
        remainingSeconds = max(1, settings.workSeconds)
        totalSeconds = remainingSeconds
        onChange?()
    }

    func applySettings(_ newSettings: Settings) {
        settings = newSettings
        settings.save()
        resetToWork()
        if isRunning {
            scheduleTimer()
        }
    }

    func skip() {
        switchPhase()
    }

    func startRestNow() {
        phase = .rest
        remainingSeconds = max(1, settings.restSeconds)
        totalSeconds = remainingSeconds
        onRestStarted?()
        onChange?()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tick() {
        guard isRunning else { return }
        stats.record(phase)
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            switchPhase()
        } else {
            onChange?()
        }
    }

    private func switchPhase() {
        if phase == .work {
            phase = .rest
            remainingSeconds = max(1, settings.restSeconds)
            totalSeconds = remainingSeconds
            onRestStarted?()
        } else {
            phase = .work
            remainingSeconds = max(1, settings.workSeconds)
            totalSeconds = remainingSeconds
        }
        onChange?()
    }
}

final class RestPanelController: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "看向远处，放松一下")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "我知道了", target: nil, action: nil)

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.cornerRadius = 18
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = NSTextField(labelWithString: "把视线从屏幕移开，给眼睛一小段恢复时间。")
        hintLabel.font = NSFont.systemFont(ofSize: 14)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        countdownLabel.alignment = .center
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(titleLabel)
        content.addSubview(hintLabel)
        content.addSubview(countdownLabel)
        content.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            hintLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            countdownLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 18),
            countdownLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            closeButton.topAnchor.constraint(equalTo: countdownLabel.bottomAnchor, constant: 18),
            closeButton.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        ])
    }

    func update(seconds: Int) {
        countdownLabel.stringValue = formatRestElapsed(seconds)
    }

    func show() {
        window?.center()
        window?.alphaValue = 0
        window?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window = window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        }
    }

    @objc private func closePanel() {
        window?.orderOut(nil)
    }
}

final class ReminderOverlayView: NSView {
    private let style: ReminderStyle
    private var pulse: CGFloat = 0

    init(style: ReminderStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPulse(_ value: CGFloat) {
        pulse = value
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dimAlpha: CGFloat = 0.13 * pulse
        NSColor.black.withAlphaComponent(dimAlpha).setFill()
        bounds.fill()
    }
}

final class RestReminderController {
    private let softCard = RestPanelController()
    private var overlayWindows: [NSWindow] = []
    private var overlayViews: [ReminderOverlayView] = []
    private var pulseTimer: Timer?
    private var pulseElapsed: TimeInterval = 0
    private var activeStyle: ReminderStyle = .softCard

    func show(style: ReminderStyle, seconds: Int) {
        hide()
        activeStyle = style
        if style == .softCard {
            softCard.update(seconds: 0)
            softCard.show()
            return
        }

        for screen in NSScreen.screens {
            let view = ReminderOverlayView(style: style)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.contentView = view
            window.alphaValue = 0
            overlayWindows.append(window)
            overlayViews.append(view)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                window.animator().alphaValue = 1
            }
        }

        startPulse()
    }

    func update(seconds: Int) {
        if activeStyle == .softCard {
            softCard.update(seconds: seconds)
        }
    }

    func hide() {
        softCard.hide()
        pulseTimer?.invalidate()
        pulseTimer = nil

        let windows = overlayWindows
        overlayWindows.removeAll()
        overlayViews.removeAll()
        for window in windows {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }

    private func startPulse() {
        pulseElapsed = 0
        let interval: TimeInterval = 1.0 / 60.0
        let cycleDuration: TimeInterval = 1.7
        let maxCycles: TimeInterval = 2
        pulseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseElapsed += interval
            let cycles = self.pulseElapsed / cycleDuration
            if cycles >= maxCycles {
                self.hide()
                return
            }
            let phase = (self.pulseElapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration) * 2 * .pi
            let value = CGFloat((1 - cos(phase)) / 2)
            self.overlayViews.forEach { $0.setPulse(value) }
        }
    }
}

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let model: TimerModel
    private let presetPopup = NSPopUpButton()
    private let displayModePopup = NSPopUpButton()
    private let reminderStylePopup = NSPopUpButton()
    private let rhythmNameField = NSTextField()
    private let workHoursField = NSTextField()
    private let workMinutesField = NSTextField()
    private let workSecondsField = NSTextField()
    private let restHoursField = NSTextField()
    private let restMinutesField = NSTextField()
    private let restSecondsField = NSTextField()
    private let todayWorkValue = NSTextField(labelWithString: "0分钟")
    private let todayRestValue = NSTextField(labelWithString: "0分钟")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "开机自启动", target: nil, action: nil)
    private let saveStatusLabel = NSTextField(labelWithString: "")
    private var saveFeedbackTimer: Timer?
    private var isUpdatingFields = false

    init(model: TimerModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 315, height: 462),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LookAway"
        window.center()
        super.init(window: window)
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "LookAway")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .left

        let subtitle = NSTextField(labelWithString: "让目光离开屏幕片刻，给眼睛一点远方。")
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .left

        presetPopup.addItems(withTitles: ["20-20-20", "番茄钟 25/5", "深度专注 50/10", "自定义"])
        presetPopup.target = self
        presetPopup.action = #selector(applyPreset)

        displayModePopup.addItems(withTitles: ["完整 h:mm:ss / m:ss", "简约 hhm / mm"])
        reminderStylePopup.addItems(withTitles: ["轻唤卡片（强提醒）", "眨眼渐暗（弱提醒）"])

        rhythmNameField.placeholderString = "我的节奏"
        rhythmNameField.delegate = self

        configureDurationField(workHoursField)
        configureDurationField(workMinutesField)
        configureDurationField(workSecondsField)
        configureDurationField(restHoursField)
        configureDurationField(restMinutesField)
        configureDurationField(restSecondsField)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        saveStatusLabel.textColor = .secondaryLabelColor
        saveStatusLabel.alignment = .right

        let timingGrid = NSGridView(views: [
            [label("节奏"), presetPopup],
            [label("名称"), rhythmNameField],
            [label("专注"), durationStack(hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)],
            [label("休息"), durationStack(hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)],
            [label("显示"), displayModePopup],
            [label("提醒"), reminderStylePopup],
            [label("启动"), launchAtLoginCheckbox]
        ])
        timingGrid.column(at: 0).xPlacement = .trailing
        timingGrid.rowSpacing = 12
        timingGrid.columnSpacing = 10

        todayWorkValue.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        todayRestValue.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let statsGrid = NSGridView(views: [
            [label("今日专注"), todayWorkValue],
            [label("今日休息"), todayRestValue]
        ])
        statsGrid.column(at: 0).xPlacement = .trailing
        statsGrid.rowSpacing = 10
        statsGrid.columnSpacing = 10

        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actionButtons = NSStackView(views: [saveStatusLabel, actionSpacer, saveButton])
        actionButtons.orientation = .horizontal
        actionButtons.alignment = .centerY
        actionButtons.spacing = 8

        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 42).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 5

        let header = NSStackView(views: [iconView, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let stack = NSStackView(views: [header, timingGrid, statsGrid, actionButtons])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])
    }

    private func configureDurationField(_ field: NSTextField) {
        field.alignment = .right
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.placeholderString = "0"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func durationStack(hours: NSTextField, minutes: NSTextField, seconds: NSTextField) -> NSStackView {
        let stack = NSStackView(views: [
            hours, label("时"),
            minutes, label("分"),
            seconds, label("秒")
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = .secondaryLabelColor
        return field
    }

    func refresh() {
        isUpdatingFields = true
        setDuration(model.settings.workSeconds, hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)
        setDuration(model.settings.restSeconds, hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)
        rhythmNameField.stringValue = model.settings.rhythmName
        displayModePopup.selectItem(at: model.settings.timeDisplayMode == .full ? 0 : 1)
        switch model.settings.reminderStyle {
        case .softCard:
            reminderStylePopup.selectItem(at: 0)
        case .dimScreen:
            reminderStylePopup.selectItem(at: 1)
        }
        launchAtLoginCheckbox.state = LaunchAtLoginManager.isEnabled ? .on : .off
        selectPresetForCurrentValues()
        refreshNameField()
        refreshStats()
        isUpdatingFields = false
    }

    func refreshStats() {
        todayWorkValue.stringValue = formatDuration(model.stats.workSeconds)
        todayRestValue.stringValue = formatDuration(model.stats.restSeconds)
    }

    @objc private func saveSettings() {
        let work = durationSeconds(hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)
        let rest = durationSeconds(hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)
        let selectedIndex = presetPopup.indexOfSelectedItem
        let customName = rhythmNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var settings = model.settings
        settings.workSeconds = work
        settings.restSeconds = rest
        settings.isCustomRhythm = selectedIndex == 3
        settings.rhythmName = settings.isCustomRhythm ? (customName.isEmpty ? "我的节奏" : customName) : presetTitle(for: selectedIndex)
        settings.timeDisplayMode = displayModePopup.indexOfSelectedItem == 0 ? .full : .compact
        switch reminderStylePopup.indexOfSelectedItem {
        case 1:
            settings.reminderStyle = .dimScreen
        default:
            settings.reminderStyle = .softCard
        }
        model.applySettings(settings)
        do {
            try LaunchAtLoginManager.setEnabled(launchAtLoginCheckbox.state == .on)
            showSaveFeedback("已保存")
        } catch {
            showError("自启动设置失败：\(error.localizedDescription)")
            launchAtLoginCheckbox.state = LaunchAtLoginManager.isEnabled ? .on : .off
        }
        refresh()
    }

    private func showSaveFeedback(_ message: String) {
        saveFeedbackTimer?.invalidate()
        saveStatusLabel.stringValue = message
        saveStatusLabel.textColor = NSColor.systemGreen
        saveFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.saveStatusLabel.stringValue = ""
            self?.saveStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func showError(_ message: String) {
        guard let window = window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    @objc private func applyPreset() {
        isUpdatingFields = true
        switch presetPopup.indexOfSelectedItem {
        case 0:
            setDuration(20 * 60, hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)
            setDuration(20, hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)
            rhythmNameField.stringValue = presetTitle(for: 0)
        case 1:
            setDuration(25 * 60, hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)
            setDuration(5 * 60, hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)
            rhythmNameField.stringValue = presetTitle(for: 1)
        case 2:
            setDuration(50 * 60, hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)
            setDuration(10 * 60, hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)
            rhythmNameField.stringValue = presetTitle(for: 2)
        default:
            if rhythmNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBuiltInTitle(rhythmNameField.stringValue) {
                rhythmNameField.stringValue = model.settings.isCustomRhythm ? model.settings.rhythmName : "我的节奏"
            }
            break
        }
        refreshNameField()
        isUpdatingFields = false
    }

    private func setDuration(_ totalSeconds: Int, hours: NSTextField, minutes: NSTextField, seconds: NSTextField) {
        let clamped = max(0, totalSeconds)
        hours.stringValue = "\(clamped / 3600)"
        minutes.stringValue = "\((clamped % 3600) / 60)"
        seconds.stringValue = "\(clamped % 60)"
    }

    private func durationSeconds(hours: NSTextField, minutes: NSTextField, seconds: NSTextField) -> Int {
        let total = max(0, hours.integerValue) * 3600 + max(0, minutes.integerValue) * 60 + max(0, seconds.integerValue)
        return max(1, total)
    }

    private func selectPresetForCurrentValues() {
        if model.settings.isCustomRhythm {
            presetPopup.selectItem(at: 3)
            return
        }
        let work = durationSeconds(hours: workHoursField, minutes: workMinutesField, seconds: workSecondsField)
        let rest = durationSeconds(hours: restHoursField, minutes: restMinutesField, seconds: restSecondsField)
        if work == 20 * 60 && rest == 20 {
            presetPopup.selectItem(at: 0)
        } else if work == 25 * 60 && rest == 5 * 60 {
            presetPopup.selectItem(at: 1)
        } else if work == 50 * 60 && rest == 10 * 60 {
            presetPopup.selectItem(at: 2)
        } else {
            presetPopup.selectItem(at: 3)
        }
    }

    private func refreshNameField() {
        let isCustom = presetPopup.indexOfSelectedItem == 3
        rhythmNameField.isEnabled = isCustom
        rhythmNameField.textColor = isCustom ? .labelColor : .secondaryLabelColor
    }

    private func presetTitle(for index: Int) -> String {
        switch index {
        case 0:
            return "20-20-20"
        case 1:
            return "番茄钟 25/5"
        case 2:
            return "深度专注 50/10"
        default:
            return "我的节奏"
        }
    }

    private func isBuiltInTitle(_ title: String) -> Bool {
        return ["20-20-20", "番茄钟 25/5", "深度专注 50/10"].contains(title)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isUpdatingFields, let field = obj.object as? NSTextField else { return }
        if field != rhythmNameField {
            presetPopup.selectItem(at: 3)
            if rhythmNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBuiltInTitle(rhythmNameField.stringValue) {
                rhythmNameField.stringValue = model.settings.isCustomRhythm ? model.settings.rhythmName : "我的节奏"
            }
            refreshNameField()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TimerModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private let restReminder = RestReminderController()
    private let statusMenu = NSMenu()
    private let stateMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseMenuItem = NSMenuItem(title: "暂停", action: #selector(toggleRunning), keyEquivalent: "")
    private let resetMenuItem = NSMenuItem(title: "重置", action: #selector(resetTimer), keyEquivalent: "")
    private let restMenuItem = NSMenuItem(title: "跳到休息", action: #selector(startRestNow), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
    private let quitMenuItem = NSMenuItem(title: "退出 LookAway", action: #selector(quitApp), keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        model.onChange = { [weak self] in self?.refreshUI() }
        model.onRestStarted = { [weak self] in self?.startRestReminder() }
        model.start()
        refreshUI()
    }

    private func configureStatusItem() {
        stateMenuItem.isEnabled = false
        for item in [pauseMenuItem, resetMenuItem, restMenuItem, settingsMenuItem, quitMenuItem] {
            item.target = self
        }
        statusMenu.addItem(stateMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(pauseMenuItem)
        statusMenu.addItem(resetMenuItem)
        statusMenu.addItem(restMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(settingsMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quitMenuItem)
        statusItem.menu = statusMenu
    }

    private func refreshUI() {
        let visibleSeconds = model.phase == .rest ? restElapsedSeconds() : model.remainingSeconds
        statusItem.button?.image = nil
        statusItem.button?.title = model.phase == .rest ? formatRestElapsed(visibleSeconds) : formatStatusTime(visibleSeconds, mode: model.settings.timeDisplayMode)
        statusItem.button?.toolTip = model.phase == .work ? "专注计时中，点击打开菜单" : "休息计时中，点击打开菜单"
        refreshMenu()
        settingsWindow.refreshStats()
        if model.phase == .rest {
            restReminder.update(seconds: restElapsedSeconds())
        } else {
            restReminder.hide()
        }
    }

    private func startRestReminder() {
        restReminder.show(style: model.settings.reminderStyle, seconds: 0)
    }

    private func refreshMenu() {
        if model.phase == .work {
            stateMenuItem.title = "专注中 · 还剩 \(formatStatusTime(model.remainingSeconds, mode: model.settings.timeDisplayMode))"
        } else {
            stateMenuItem.title = "休息中 · 已休息 \(formatRestElapsed(restElapsedSeconds()))"
        }
        pauseMenuItem.title = model.isRunning ? "暂停" : "继续"
        restMenuItem.title = model.phase == .work ? "跳到休息" : "结束休息"
    }

    private func restElapsedSeconds() -> Int {
        return max(0, model.totalSeconds - model.remainingSeconds)
    }

    @objc private func toggleRunning() {
        model.isRunning ? model.pause() : model.start()
        refreshUI()
    }

    @objc private func resetTimer() {
        model.resetToWork()
        refreshUI()
    }

    @objc private func startRestNow() {
        if model.phase == .work {
            model.startRestNow()
        } else {
            model.resetToWork()
        }
        refreshUI()
    }

    @objc private func openSettings() {
        settingsWindow.refresh()
        settingsWindow.showWindow(nil)
        settingsWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

}

func formatStatusTime(_ seconds: Int, mode: TimeDisplayMode) -> String {
    let clamped = max(0, seconds)
    switch mode {
    case .full:
        return format(clamped)
    case .compact:
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        if clamped == 0 {
            return "0m"
        }
        return "\(max(1, minutes))m"
    }
}

func formatRestElapsed(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let minutes = clamped / 60
    let remainder = clamped % 60
    if minutes > 0 {
        return String(format: "%dm %02ds", minutes, remainder)
    }
    return "\(clamped)s"
}

func format(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let remainder = clamped % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }
    return String(format: "%02d:%02d", minutes, remainder)
}

func formatDuration(_ seconds: Int) -> String {
    let clamped = max(0, seconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let remainder = clamped % 60
    if hours > 0 {
        return "\(hours)小时 \(minutes)分钟"
    }
    if minutes > 0 {
        return "\(minutes)分钟 \(remainder)秒"
    }
    return "\(remainder)秒"
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
