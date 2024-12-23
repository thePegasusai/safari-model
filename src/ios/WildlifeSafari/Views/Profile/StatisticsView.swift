//
// StatisticsView.swift
// WildlifeSafari
//
// Enterprise-grade statistics dashboard providing comprehensive user engagement metrics,
// discovery analytics, and achievements with offline support and data visualization.
//

import SwiftUI // latest
import Charts // latest

// MARK: - Constants

private enum Constants {
    static let chartHeight: CGFloat = 250
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 12
    static let minimumAccuracyThreshold: Double = 0.7
    static let animationDuration: Double = 0.3
    static let maxDiscoveriesPerPage: Int = 50
}

// MARK: - StatisticsView

@MainActor
struct StatisticsView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var selectedTimeRange: TimeRange = .month
    @State private var showingAchievements: Bool = false
    @State private var chartStyle: ChartStyle = .combined
    @State private var isRefreshing: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Sync Status Indicator
                if viewModel.syncStatus != .synced {
                    syncStatusBanner
                }
                
                // Time Range Selector
                timeRangeSelector
                    .padding(.horizontal)
                
                // Loading State
                if viewModel.isLoading {
                    ProgressView("Loading statistics...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // Statistics Content
                    LazyVStack(spacing: 24) {
                        discoveryStatsCard
                            .transition(.opacity)
                        
                        accuracyChart
                            .frame(height: Constants.chartHeight)
                            .transition(.opacity)
                        
                        speciesDiversityStats
                            .transition(.opacity)
                        
                        achievementsSection
                            .transition(.opacity)
                    }
                    .padding(.horizontal)
                }
            }
            .refreshable {
                await refreshStatistics()
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityElement(children: .contain)
    }
    
    // MARK: - Components
    
    private var syncStatusBanner: some View {
        HStack {
            Image(systemName: "icloud.and.arrow.up")
            Text("Syncing statistics...")
            Spacer()
            ProgressView()
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    private var timeRangeSelector: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            Text("Week").tag(TimeRange.week)
            Text("Month").tag(TimeRange.month)
            Text("Year").tag(TimeRange.year)
            Text("Custom").tag(TimeRange.custom(DateInterval()))
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTimeRange) { _ in
            withAnimation(.easeInOut(duration: Constants.animationDuration)) {
                // Trigger statistics update for new time range
            }
        }
    }
    
    private var discoveryStatsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Total Discoveries
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Discoveries")
                        .font(.headline)
                    Text("\(viewModel.discoveries.count)")
                        .font(.largeTitle.bold())
                }
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.title2)
            }
            
            Divider()
            
            // Discovery Breakdown
            HStack {
                discoveryTypeStats(
                    title: "Wildlife",
                    count: wildlifeCount,
                    icon: "leaf.fill"
                )
                Spacer()
                discoveryTypeStats(
                    title: "Fossils",
                    count: fossilCount,
                    icon: "fossil.shell.fill"
                )
            }
            
            // Verification Status
            verificationProgressBar
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .fill(Color.secondary.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
    }
    
    private func discoveryTypeStats(title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            Text("\(count)")
                .font(.title2.bold())
        }
    }
    
    private var verificationProgressBar: some View {
        VStack(alignment: .leading) {
            Text("Verification Status")
                .font(.subheadline)
            
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * verifiedRatio)
                    
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geometry.size.width * pendingRatio)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)
            
            HStack {
                Text("Verified: \(Int(verifiedRatio * 100))%")
                    .foregroundColor(.green)
                Spacer()
                Text("Pending: \(Int(pendingRatio * 100))%")
                    .foregroundColor(.orange)
            }
            .font(.caption)
        }
    }
    
    private var accuracyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detection Accuracy")
                    .font(.headline)
                Spacer()
                chartStylePicker
            }
            
            Chart {
                ForEach(accuracyData, id: \.date) { dataPoint in
                    switch chartStyle {
                    case .line:
                        LineMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Accuracy", dataPoint.accuracy)
                        )
                    case .bar:
                        BarMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Accuracy", dataPoint.accuracy)
                        )
                    case .scatter:
                        PointMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Accuracy", dataPoint.accuracy)
                        )
                    case .combined:
                        LineMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Accuracy", dataPoint.accuracy)
                        )
                        PointMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Accuracy", dataPoint.accuracy)
                        )
                    }
                }
                
                RuleMark(
                    y: .value("Threshold", Constants.minimumAccuracyThreshold)
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        Text("\(value.as(Double.self)?.formatted(.percent) ?? "")")
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    private var chartStylePicker: some View {
        Picker("Chart Style", selection: $chartStyle) {
            Image(systemName: "chart.xyaxis.line").tag(ChartStyle.line)
            Image(systemName: "chart.bar").tag(ChartStyle.bar)
            Image(systemName: "chart.scatter").tag(ChartStyle.scatter)
            Image(systemName: "chart.line.uptrend.xyaxis").tag(ChartStyle.combined)
        }
        .pickerStyle(.segmented)
    }
    
    private var speciesDiversityStats: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Species Diversity")
                .font(.headline)
            
            HStack {
                diversityMetric(
                    title: "Unique Species",
                    value: uniqueSpeciesCount,
                    icon: "leaf.arrow.triangle.circlepath"
                )
                Spacer()
                diversityMetric(
                    title: "Endangered",
                    value: endangeredCount,
                    icon: "exclamationmark.triangle"
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    private func diversityMetric(title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            Text("\(value)")
                .font(.title2.bold())
        }
    }
    
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showingAchievements.toggle()
            } label: {
                HStack {
                    Text("Achievements")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
            .sheet(isPresented: $showingAchievements) {
                // Achievement detail view would be presented here
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(achievements) { achievement in
                        achievementCard(achievement)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    private func achievementCard(_ achievement: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: achievement.icon)
                .font(.title)
            
            Text(achievement.title)
                .font(.headline)
            
            Text(achievement.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView(value: achievement.progress)
                .tint(achievement.isCompleted ? .green : .blue)
        }
        .frame(width: 150)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .fill(Color.secondary.opacity(0.05))
        )
    }
    
    // MARK: - Computed Properties
    
    private var wildlifeCount: Int {
        viewModel.discoveries.filter { $0.type == .wildlife }.count
    }
    
    private var fossilCount: Int {
        viewModel.discoveries.filter { $0.type == .fossil }.count
    }
    
    private var verifiedRatio: Double {
        let verifiedCount = Double(viewModel.discoveries.filter { $0.verificationStatus == .verified }.count)
        return verifiedCount / Double(max(viewModel.discoveries.count, 1))
    }
    
    private var pendingRatio: Double {
        1.0 - verifiedRatio
    }
    
    private var accuracyData: [(date: Date, accuracy: Double)] {
        viewModel.discoveries
            .sorted { $0.timestamp < $1.timestamp }
            .map { (date: $0.timestamp, accuracy: $0.confidence) }
    }
    
    private var uniqueSpeciesCount: Int {
        Set(viewModel.discoveries.compactMap { $0.species?.id }).count
    }
    
    private var endangeredCount: Int {
        viewModel.discoveries.filter { $0.species?.isEndangered == true }.count
    }
    
    private var achievements: [Achievement] {
        // Achievement data would be computed here
        []
    }
    
    // MARK: - Methods
    
    private func refreshStatistics() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Refresh logic would be implemented here
    }
}

// MARK: - Supporting Types

private struct Achievement: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let icon: String
    let progress: Double
    let isCompleted: Bool
}

// MARK: - Preview

#Preview {
    StatisticsView(viewModel: ProfileViewModel(
        authService: AuthenticationService(),
        collectionService: CollectionService(
            apiClient: APIClient(),
            coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
            syncService: SyncService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
            )
        ),
        secureStorage: KeychainManager.shared,
        errorHandler: ErrorHandler(),
        analyticsTracker: AnalyticsTracker()
    ))
}