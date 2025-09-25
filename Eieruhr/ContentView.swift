//
//  ContentView.swift
//  Eieruhr
//
//  Created by Adrian Gier on 25.09.25.
//

import SwiftUI
import CoreData
import UserNotifications
import Combine

// MARK: - Enums for User Input

enum EggSize: String, CaseIterable, Codable {
    case small = "S"
    case medium = "M"
    case large = "L"
    
    var displayName: String {
        switch self {
        case .small: return "Klein (S)"
        case .medium: return "Mittel (M)"
        case .large: return "Groß (L)"
        }
    }
    
    var defaultWeight: Double {
        switch self {
        case .small: return 45.0  // Gramm
        case .medium: return 55.0
        case .large: return 65.0
        }
    }
}

enum EggConsistency: String, CaseIterable, Codable {
    case soft = "weich"
    case medium = "medium"
    case hard = "hart"
    
    var displayName: String {
        switch self {
        case .soft: return "Weich"
        case .medium: return "Medium"
        case .hard: return "Hart"
        }
    }
    
    // Zieltemperatur Eigelb in Celsius
    var targetTemperature: Double {
        switch self {
        case .soft: return 63.0
        case .medium: return 65.0
        case .hard: return 70.0
        }
    }
}

enum StartingTemperature: String, CaseIterable, Codable {
    case fridge = "kühlschrank"
    case room = "raumtemperatur"
    
    var displayName: String {
        switch self {
        case .fridge: return "Kühlschrank (4°C)"
        case .room: return "Raumtemperatur (20°C)"
        }
    }
    
    var temperature: Double {
        switch self {
        case .fridge: return 4.0
        case .room: return 20.0
        }
    }
}

enum WaterStart: String, CaseIterable, Codable {
    case cold = "kalt"
    case boiling = "kochend"
    
    var displayName: String {
        switch self {
        case .cold: return "Kalt"
        case .boiling: return "Kochend"
        }
    }
    
    // Ungefähre Zeit zum Aufheizen von 1L Wasser
    var heatupTime: TimeInterval {
        switch self {
        case .cold: return 360.0 // ~6 Minuten für 1L Wasser von 20°C auf 100°C
        case .boiling: return 0.0
        }
    }
}

// MARK: - Egg Parameters Model

struct EggParameters: Codable {
    let size: EggSize
    let weight: Double // in Gramm
    let startingTemperature: StartingTemperature
    let consistency: EggConsistency
    let waterStart: WaterStart
    
    init(size: EggSize = .medium, 
         weight: Double? = nil, 
         startingTemperature: StartingTemperature = .fridge, 
         consistency: EggConsistency = .medium,
         waterStart: WaterStart = .boiling) {
        self.size = size
        self.weight = weight ?? size.defaultWeight
        self.startingTemperature = startingTemperature
        self.consistency = consistency
        self.waterStart = waterStart
    }
}

// MARK: - Physics Constants

struct PhysicsConstants {
    static let waterTemperature: Double = 100.0  // Tw in Celsius
    static let heatCapacity: Double = 3.7        // c in J/gK
    static let density: Double = 1.038           // ρ in g/cm³
    static let dimensionlessFactor: Double = 1.0 // K
    static let pi = Double.pi
}

// MARK: - Validation Result

enum ValidationResult {
    case valid
    case invalid([String])
    
    var isValid: Bool {
        switch self {
        case .valid: return true
        case .invalid: return false
        }
    }
    
    var errorMessages: [String] {
        switch self {
        case .valid: return []
        case .invalid(let errors): return errors
        }
    }
}

// MARK: - Egg Calculation Engine

class EggCalculationEngine {
    
    /// Berechnet die Gesamtzeit inkl. Kaltstart und Kochzeit
    /// Kaltstart: Zeit zum Aufheizen des Wassers
    /// Kochzeit: Physikalische Formel für Ei-Garung
    static func calculateCookingTime(for parameters: EggParameters) -> TimeInterval {
        let eggCookingTime = calculateEggCookingTime(for: parameters)
        let waterHeatupTime = parameters.waterStart.heatupTime
        
        return waterHeatupTime + eggCookingTime
    }
    
    /// Berechnet nur die reine Ei-Kochzeit basierend auf der physikalischen Formel
    /// t = (M^(2/3) * c * ρ^(1/3)) / (K * π² * α) * ln[0.76 * (T0 - Tw) / (Ty - Tw)]
    /// Corrected formula based on heat transfer physics
    private static func calculateEggCookingTime(for parameters: EggParameters) -> TimeInterval {
        let tw = PhysicsConstants.waterTemperature
        let t0 = parameters.startingTemperature.temperature
        let ty = parameters.consistency.targetTemperature
        let m = parameters.weight  // Keep in grams
        let c = PhysicsConstants.heatCapacity
        let rho = PhysicsConstants.density  // Keep in g/cm³
        let k = PhysicsConstants.dimensionlessFactor
        let pi = PhysicsConstants.pi
        
        // Thermal diffusivity approximation for egg (cm²/s)
        let alpha = 0.0011
        
        // Validate inputs
        guard tw > ty, tw > t0, m > 0 else {
            print("Invalid parameters for egg calculation")
            return 180 // Default 3 minutes if calculation fails
        }
        
        // Calculate the logarithmic term - corrected
        let numerator = 0.76 * (t0 - tw)
        let denominator = (ty - tw)
        
        guard denominator != 0, numerator / denominator > 0 else {
            print("Invalid logarithmic calculation - using fallback")
            // Fallback calculation based on empirical data
            let baseTime = 180.0 // 3 minutes base
            let weightFactor = pow(m / 55.0, 0.67) // Scale with weight
            let tempFactor = (ty - t0) / (100.0 - t0) // Scale with temperature difference
            let consistencyFactor = parameters.consistency == .soft ? 0.8 : 
                                  parameters.consistency == .medium ? 1.0 : 1.3
            return baseTime * weightFactor * tempFactor * consistencyFactor
        }
        
        let lnTerm = log(numerator / denominator)
        
        // Calculate using corrected formula (result in seconds)
        let time = (pow(m, 2.0/3.0) * c * pow(rho, 1.0/3.0)) / (k * pi * pi * alpha) * lnTerm
        
        // The result should be positive and reasonable (2-15 minutes)
        let result = abs(time)
        
        // Sanity check and scaling factor adjustment
        if result < 60 || result > 1200 {
            // Use empirical fallback if physics calculation seems off
            let baseTime = 240.0 // 4 minutes base
            let weightFactor = pow(m / 55.0, 0.67)
            let tempFactor = parameters.startingTemperature == .fridge ? 1.2 : 1.0
            let consistencyFactor = parameters.consistency == .soft ? 0.7 : 
                                  parameters.consistency == .medium ? 1.0 : 1.4
            return baseTime * weightFactor * tempFactor * consistencyFactor
        }
        
        return result
    }
    
    /// Validiert die Eingabeparameter
    static func validateParameters(_ parameters: EggParameters) -> ValidationResult {
        var errors: [String] = []
        
        if parameters.weight < 30 || parameters.weight > 90 {
            errors.append("Gewicht muss zwischen 30g und 90g liegen")
        }
        
        if errors.isEmpty {
            return .valid
        } else {
            return .invalid(errors)
        }
    }
}

// MARK: - ViewModel

@MainActor
class EggTimerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var eggParameters = EggParameters()
    @Published var calculatedTime: TimeInterval = 0
    @Published var remainingTime: TimeInterval = 0
    @Published var isTimerRunning = false
    @Published var isTimerPaused = false
    @Published var validationErrors: [String] = []
    @Published var showingTimerView = false
    @Published var previewCalculatedTime: TimeInterval = 0
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    
    // MARK: - Computed Properties
    
    var formattedRemainingTime: String {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var progress: Double {
        guard calculatedTime > 0 else { return 0 }
        return 1.0 - (remainingTime / calculatedTime)
    }
    
    var formattedPreviewTime: String {
        let minutes = Int(previewCalculatedTime) / 60
        let seconds = Int(previewCalculatedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Input Methods
    
    func updateEggSize(_ size: EggSize) {
        eggParameters = EggParameters(
            size: size,
            weight: size.defaultWeight,
            startingTemperature: eggParameters.startingTemperature,
            consistency: eggParameters.consistency,
            waterStart: eggParameters.waterStart
        )
        clearValidationErrors()
        updatePreviewTime()
    }
    
    func updateWeight(_ weight: Double) {
        eggParameters = EggParameters(
            size: eggParameters.size,
            weight: weight,
            startingTemperature: eggParameters.startingTemperature,
            consistency: eggParameters.consistency,
            waterStart: eggParameters.waterStart
        )
        clearValidationErrors()
        updatePreviewTime()
    }
    
    func updateStartingTemperature(_ temperature: StartingTemperature) {
        eggParameters = EggParameters(
            size: eggParameters.size,
            weight: eggParameters.weight,
            startingTemperature: temperature,
            consistency: eggParameters.consistency,
            waterStart: eggParameters.waterStart
        )
        clearValidationErrors()
        updatePreviewTime()
    }
    
    func updateConsistency(_ consistency: EggConsistency) {
        eggParameters = EggParameters(
            size: eggParameters.size,
            weight: eggParameters.weight,
            startingTemperature: eggParameters.startingTemperature,
            consistency: consistency,
            waterStart: eggParameters.waterStart
        )
        clearValidationErrors()
        updatePreviewTime()
    }
    
    func updateWaterStart(_ waterStart: WaterStart) {
        eggParameters = EggParameters(
            size: eggParameters.size,
            weight: eggParameters.weight,
            startingTemperature: eggParameters.startingTemperature,
            consistency: eggParameters.consistency,
            waterStart: waterStart
        )
        clearValidationErrors()
        updatePreviewTime()
    }
    
    // MARK: - Calculation Methods
    
    func calculateAndStartTimer() {
        let validation = EggCalculationEngine.validateParameters(eggParameters)
        
        guard validation.isValid else {
            validationErrors = validation.errorMessages
            return
        }
        
        calculatedTime = EggCalculationEngine.calculateCookingTime(for: eggParameters)
        remainingTime = calculatedTime
        
        // Request notification permission
        requestNotificationPermission()
        
        showingTimerView = true
        startTimer()
    }
    
    // MARK: - Preview Time Calculation
    
    func updatePreviewTime() {
        let validation = EggCalculationEngine.validateParameters(eggParameters)
        if validation.isValid {
            previewCalculatedTime = EggCalculationEngine.calculateCookingTime(for: eggParameters)
        } else {
            previewCalculatedTime = 0
        }
    }
    
    // MARK: - Timer Control Methods
    
    func startTimer() {
        guard !isTimerRunning else { return }
        
        isTimerRunning = true
        isTimerPaused = false
        showingTimerView = true
        
        // Schedule notification
        scheduleNotification()
        
        // Start the timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                if self.remainingTime > 0 {
                    self.remainingTime -= 1
                } else {
                    self.stopAndReturn()
                }
            }
        }
    }
    
    func pauseTimer() {
        guard isTimerRunning else { return }
        
        isTimerRunning = false
        isTimerPaused = true
        
        timer?.invalidate()
        timer = nil
        
        // Cancel notification
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func resetTimer() {
        timer?.invalidate()
        timer = nil
        
        isTimerRunning = false
        isTimerPaused = false
        remainingTime = calculatedTime
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func stopAndReturn() {
        resetTimer()
        showingTimerView = false
    }
    
    // MARK: - Notification Methods
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Eieruhr"
        content.body = "Dein Ei ist fertig! 🥚"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remainingTime, repeats: false)
        let request = UNNotificationRequest(identifier: "eggTimer", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error)")
            }
        }
    }
    
    // MARK: - Favorites Methods
    
    func saveAsFavorite() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(eggParameters) {
            UserDefaults.standard.set(data, forKey: "favoriteEggParameters")
        }
    }
    
    func loadFavorite() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "favoriteEggParameters"),
           let parameters = try? decoder.decode(EggParameters.self, from: data) {
            eggParameters = parameters
            updatePreviewTime()
        }
    }
    
    // MARK: - Validation Methods
    
    private func clearValidationErrors() {
        validationErrors = []
    }
}

// MARK: - Main Content View

struct ContentView: View {
    var body: some View {
        EggInputView()
    }
}

// MARK: - Input View

struct EggInputView: View {
    @StateObject private var viewModel = EggTimerViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.showingTimerView {
                    // Timer View
                    EggTimerView(viewModel: viewModel)
                } else {
                    // Setup View
                    VStack(spacing: 8) {
                        // Header
                        headerSection
                        
                        // Input Form
                        VStack(spacing: 12) {
                            eggSizeSection
                            weightSection
                            temperatureSection
                            consistencySection
                            waterStartSection
                        }
                        .padding(.horizontal)
                        
                        // Validation Errors
                        if !viewModel.validationErrors.isEmpty {
                            errorSection
                        }
                        
                        // Calculated Time Display
                        calculatedTimeSection
                        
                        // Calculate Button
                        calculateButton
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .navigationTitle("")
                    .preferredColorScheme(.light)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button("Favorit laden", action: viewModel.loadFavorite)
                                Button("Als Favorit speichern", action: viewModel.saveAsFavorite)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.updatePreviewTime()
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        Image("egg-logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 120, height: 120)
            .shadow(color: .orange.opacity(0.3), radius: 12, x: 0, y: 6)
    }
    
    private var eggSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ei-Größe", systemImage: "scalemass")
                .font(.headline)
            
            Picker("Ei-Größe", selection: Binding(
                get: { viewModel.eggParameters.size },
                set: { viewModel.updateEggSize($0) }
            )) {
                ForEach(EggSize.allCases, id: \.self) { size in
                    Text(size.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .tag(size)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(20)
        }
        .padding(.vertical, 4)
    }
    
    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Gewicht", systemImage: "scalemass.fill")
                    .font(.headline)
                
                Spacer()
                
                Text("\(Int(viewModel.eggParameters.weight))g")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            
            Slider(
                value: Binding(
                    get: { viewModel.eggParameters.weight },
                    set: { viewModel.updateWeight($0) }
                ),
                in: 30...90,
                step: 1
            ) {
                Text("Gewicht")
            } minimumValueLabel: {
                Text("30g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } maximumValueLabel: {
                Text("90g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accentColor(.orange)
        }
        .padding(.vertical, 8)
    }
    
    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ausgangstemperatur", systemImage: "thermometer")
                .font(.headline)
            
            Picker("Ausgangstemperatur", selection: Binding(
                get: { viewModel.eggParameters.startingTemperature },
                set: { viewModel.updateStartingTemperature($0) }
            )) {
                ForEach(StartingTemperature.allCases, id: \.self) { temp in
                    Text(temp.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .tag(temp)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(20)
        }
        .padding(.vertical, 4)
    }
    
    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Konsistenz", systemImage: "drop.fill")
                .font(.headline)
            
            Picker("Konsistenz", selection: Binding(
                get: { viewModel.eggParameters.consistency },
                set: { viewModel.updateConsistency($0) }
            )) {
                ForEach(EggConsistency.allCases, id: \.self) { consistency in
                    Text(consistency.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .tag(consistency)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.2))
            .cornerRadius(20)
        }
        .padding(.vertical, 4)
    }
    
    private var waterStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wasserstart", systemImage: "flame.fill")
                .font(.headline)
            
            Picker("Wasserstart", selection: Binding(
                get: { viewModel.eggParameters.waterStart },
                set: { viewModel.updateWaterStart($0) }
            )) {
                ForEach(WaterStart.allCases, id: \.self) { waterStart in
                    Text(waterStart.displayName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .tag(waterStart)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.2))
            .cornerRadius(20)
        }
        .padding(.vertical, 4)
    }
    
    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.validationErrors, id: \.self) { error in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var calculatedTimeSection: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.orange)
            Text("Berechnete Kochzeit:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(viewModel.formattedPreviewTime)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .opacity(viewModel.previewCalculatedTime > 0 ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.3), value: viewModel.previewCalculatedTime)
    }
    
    private var calculateButton: some View {
        Button(action: viewModel.calculateAndStartTimer) {
            HStack {
                Image(systemName: "play.fill")
                Text("Timer starten")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding(.top, 8)
    }
}

// MARK: - Timer View

struct EggTimerView: View {
    @ObservedObject var viewModel: EggTimerViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    // Large custom title
                    Text("Timer läuft")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.top, 20)
                    
                    // Header with Logo and App Name
                    timerHeaderSection
                    
                    Spacer()
                    
                    // Main timer display
                    timerDisplaySection(size: geometry.size)
                    
                    Spacer()
                    
                    // Control buttons
                    controlButtonsSection
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("")
        .preferredColorScheme(.light)
    }
    
    // MARK: - Timer View Components
    
    private var timerHeaderSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                Text("Ei wird gekocht...")
                    .font(.headline)
            }
            
            HStack(spacing: 16) {
                InfoChip(
                    icon: "scalemass",
                    text: "\(Int(viewModel.eggParameters.weight))g"
                )
                
                InfoChip(
                    icon: "thermometer",
                    text: viewModel.eggParameters.startingTemperature == .fridge ? "4°C" : "20°C"
                )
                
                InfoChip(
                    icon: "drop.fill",
                    text: viewModel.eggParameters.consistency.displayName
                )
            }
        }
    }
    
    private func timerDisplaySection(size: CGSize) -> some View {
        let circleSize = min(size.width, size.height) * 0.6
        
        return ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                .frame(width: circleSize, height: circleSize)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: viewModel.progress)
                .stroke(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: circleSize, height: circleSize)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1), value: viewModel.progress)
            
            // Timer text
            VStack(spacing: 8) {
                Text(viewModel.formattedRemainingTime)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                
                Text("verbleibend")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Egg animation (simple pulsing effect when timer is running)
            if viewModel.isTimerRunning {
                Image(systemName: "oval.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange.opacity(0.3))
                    .scaleEffect(viewModel.isTimerRunning ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.isTimerRunning)
                    .offset(y: 80)
            }
        }
    }
    
    private var controlButtonsSection: some View {
        HStack(spacing: 20) {
            // Reset button
            Button(action: viewModel.resetTimer) {
                VStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                    Text("Reset")
                        .font(.caption)
                }
                .frame(width: 80, height: 60)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
            }
            .foregroundColor(.primary)
            
            Spacer()
            
            // Main control button (Play/Pause)
            Button(action: {
                if viewModel.isTimerRunning {
                    viewModel.pauseTimer()
                } else {
                    viewModel.startTimer()
                }
            }) {
                VStack {
                    Image(systemName: viewModel.isTimerRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                    Text(viewModel.isTimerRunning ? "Pause" : "Start")
                        .font(.caption)
                }
                .frame(width: 100, height: 80)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(16)
            }
            
            Spacer()
            
            // Stop button
            Button(action: {
                viewModel.stopAndReturn()
            }) {
                VStack {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                    Text("Stop")
                        .font(.caption)
                }
                .frame(width: 80, height: 60)
                .background(Color.red.opacity(0.2))
                .cornerRadius(12)
            }
            .foregroundColor(.red)
        }
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct InfoChip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
