import UIKit
import RxSwift
import RxRelay
import RxCocoa
import MarketKit
import Chart

class CoinDetailsViewModel {
    private let service: CoinDetailsService
    private let disposeBag = DisposeBag()

    private let viewItemRelay = BehaviorRelay<ViewItem?>(value: nil)
    private let loadingRelay = BehaviorRelay<Bool>(value: false)
    private let syncErrorRelay = BehaviorRelay<Bool>(value: false)

    private let ratioFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    init(service: CoinDetailsService) {
        self.service = service

        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }

        sync(state: service.state)
    }

    private func sync(state: DataStatus<CoinDetailsService.Item>) {
        switch state {
        case .loading:
            viewItemRelay.accept(nil)
            loadingRelay.accept(true)
            syncErrorRelay.accept(false)
        case .completed(let item):
            viewItemRelay.accept(viewItem(item: item))
            loadingRelay.accept(false)
            syncErrorRelay.accept(false)
        case .failed:
            viewItemRelay.accept(nil)
            loadingRelay.accept(false)
            syncErrorRelay.accept(true)
        }
    }

    private func chart(title: String, item: CoinDetailsService.ProData, description: String? = nil, currentValueType: CoinProChartModule.ChartValueType = .last, chartPreviewValuePostfix: ChartPreviewValuePostfix = .currency) -> MarketCardView.ViewItem? {
        switch item {
        case .empty: return nil
        case .completed(let values):
            guard let first = values.first, let last = values.last else {
                return nil
            }

            let chartItems = values.map {
                ChartItem(timestamp: $0.timestamp).added(name: .rate, value: $0.value)
            }

            let diffValue = (last.value / first.value - 1) * 100
            let diff = DiffLabel.formatted(value: diffValue)
            let diffColor = DiffLabel.color(value: diffValue)

            let chartData = ChartData(items: chartItems, startTimestamp: first.timestamp, endTimestamp: last.timestamp)

            var value: Decimal
            var ignoreTrend = false

            switch currentValueType {
            case .last: value = last.value
            case .cumulative:
                value = values.map { $0.value }.reduce(0, +)
                ignoreTrend = true                      // For cumulative value trend must be ignored
            }

            let valueString: String?
            switch chartPreviewValuePostfix {
            case .currency: valueString = ValueFormatter.instance.formatShort(currency: service.currency, value: value)
            case .coin: valueString = ValueFormatter.instance.formatShort(value: value).map { [$0, coin.code].joined(separator: " ") }
            case .noPostfix: valueString = ValueFormatter.instance.formatShort(value: value)
            }

            return MarketCardView.ViewItem(
                    title: title,
                    value: valueString,
                    description: ignoreTrend ? nil : diff,
                    descriptionColor: ignoreTrend ? nil : diffColor,
                    chartData: chartData,
                    movementTrend: ignoreTrend ? .ignore : (diffValue.isSignMinus ? .down : .up)
            )
        }
    }

    private func tokenLiquidity(proFeatures: CoinDetailsService.AnalyticData) -> TokenLiquidityViewItem {
        TokenLiquidityViewItem(
                volume: chart(title: CoinProChartModule.ProChartType.volume.valueTitle, item: proFeatures.dexVolumes, currentValueType: .cumulative),
                liquidity: chart(title: CoinProChartModule.ProChartType.liquidity.valueTitle, item: proFeatures.dexLiquidity, currentValueType: .last)
        )
    }

    private func tokenDistribution(proFeatures: CoinDetailsService.AnalyticData) -> TokenDistributionViewItem {
        TokenDistributionViewItem(
                txCount: chart(title: CoinProChartModule.ProChartType.txCount.valueTitle, item: proFeatures.txCount, currentValueType: .cumulative, chartPreviewValuePostfix: .noPostfix),
                txVolume: chart(title: CoinProChartModule.ProChartType.txVolume.valueTitle, item: proFeatures.txVolume, currentValueType: .cumulative, chartPreviewValuePostfix: .coin),
                activeAddresses: chart(title: CoinProChartModule.ProChartType.activeAddresses.valueTitle, item: proFeatures.activeAddresses, currentValueType: .last, chartPreviewValuePostfix: .noPostfix)
        )
    }

    private func viewItem(item: CoinDetailsService.Item) -> ViewItem {
        ViewItem(
                tokenLiquidity: tokenLiquidity(proFeatures: item.analytics),
                tokenDistribution: tokenDistribution(proFeatures: item.analytics),
                hasMajorHolders: service.hasMajorHolders,
                tvlChart: chart(title: "coin_page.chart_tvl".localized, item: item.tvls.flatMap { .completed($0) } ?? .empty),
                tvlRank: item.marketInfoDetails.tvlRank.map { "#\($0)" },
                tvlRatio: item.marketInfoDetails.tvlRatio.flatMap { ratioFormatter.string(from: $0 as NSNumber) },
                treasuries: item.marketInfoDetails.totalTreasuries.flatMap { ValueFormatter.instance.formatShort(currency: service.currency, value: $0) },
                fundsInvested: item.marketInfoDetails.totalFundsInvested.flatMap { ValueFormatter.instance.formatShort(currency: service.usdCurrency, value: $0) },
                reportsCount: item.marketInfoDetails.reportsCount == 0 ? nil : "\(item.marketInfoDetails.reportsCount)",
                securityViewItems: securityViewItems(info: item.marketInfoDetails),
                auditAddresses: service.auditAddresses
        )
    }

    private func securityViewItems(info: MarketInfoDetails) -> [SecurityViewItem] {
        var viewItems = [SecurityViewItem]()

        if let kitPrivacy = info.privacy {
            let privacy: SecurityLevel
            switch kitPrivacy {
            case .low: privacy = .low
            case .medium: privacy = .medium
            case .high: privacy = .high
            }

            viewItems.append(SecurityViewItem(type: .privacy, value: privacy.title, valueGrade: privacy.grade))
        }

        if let kitIssuance = info.decentralizedIssuance {
            let issuance: SecurityIssuance = kitIssuance ? .decentralized : .centralized
            viewItems.append(SecurityViewItem(type: .issuance, value: issuance.title, valueGrade: issuance.grade))
        }

        if let kitResistant = info.confiscationResistant {
            let resistance: SecurityConfiscationResistance = kitResistant ? .yes : .no
            viewItems.append(SecurityViewItem(type: .confiscationResistance, value: resistance.title, valueGrade: resistance.grade))
        }

        if let kitResistant = info.censorshipResistant {
            let resistance: SecurityCensorshipResistance = kitResistant ? .yes : .no
            viewItems.append(SecurityViewItem(type: .censorshipResistance, value: resistance.title, valueGrade: resistance.grade))
        }

        return viewItems
    }

}

extension CoinDetailsViewModel {

    var viewItemDriver: Driver<ViewItem?> {
        viewItemRelay.asDriver()
    }

    var loadingDriver: Driver<Bool> {
        loadingRelay.asDriver()
    }

    var syncErrorDriver: Driver<Bool> {
        syncErrorRelay.asDriver()
    }

    var coin: Coin {
        service.coin
    }

    func onLoad() {
        service.sync()
    }

    func onTapRetry() {
        service.sync()
    }

}

extension CoinDetailsViewModel {

    struct ViewItem {
        let tokenLiquidity: TokenLiquidityViewItem
        let tokenDistribution: TokenDistributionViewItem
        let hasMajorHolders: Bool
        let tvlChart: MarketCardView.ViewItem?
        let tvlRank: String?
        let tvlRatio: String?
        let treasuries: String?
        let fundsInvested: String?
        let reportsCount: String?
        let securityViewItems: [SecurityViewItem]
        let auditAddresses: [String]
    }

    struct TokenLiquidityViewItem {
        let volume: MarketCardView.ViewItem?
        let liquidity: MarketCardView.ViewItem?
    }

    struct TokenDistributionViewItem {
        let txCount: MarketCardView.ViewItem?
        let txVolume: MarketCardView.ViewItem?
        let activeAddresses: MarketCardView.ViewItem?
    }

    struct SecurityViewItem {
        let type: SecurityType
        let value: String
        let valueGrade: SecurityGrade
    }

    struct SecurityInfoViewItem {
        let grade: SecurityGrade
        let title: String
        let text: String
    }

    enum SecurityLevel: String, CaseIterable {
        case low
        case medium
        case high

        var title: String {
            "coin_page.security_parameters.level.\(rawValue)".localized
        }

        var description: String {
            "coin_page.security_parameters.privacy.description.\(rawValue)".localized
        }

        var grade: SecurityGrade {
            switch self {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            }
        }
    }

    enum SecurityIssuance: String, CaseIterable {
        case decentralized
        case centralized

        var title: String {
            "coin_page.security_parameters.issuance.\(rawValue)".localized
        }

        var description: String {
            "coin_page.security_parameters.issuance.description.\(rawValue)".localized
        }

        var grade: SecurityGrade {
            switch self {
            case .decentralized: return .high
            case .centralized: return .low
            }
        }
    }

    enum SecurityConfiscationResistance: String, CaseIterable {
        case yes
        case no

        var title: String {
            "coin_page.security_parameters.resistance.\(rawValue)".localized
        }

        var description: String {
            "coin_page.security_parameters.confiscation_resistance.description.\(rawValue)".localized
        }

        var grade: SecurityGrade {
            switch self {
            case .yes: return .high
            case .no: return .low
            }
        }
    }

    enum SecurityCensorshipResistance: String, CaseIterable {
        case yes
        case no

        var title: String {
            "coin_page.security_parameters.resistance.\(rawValue)".localized
        }

        var description: String {
            "coin_page.security_parameters.censorship_resistance.description.\(rawValue)".localized
        }

        var grade: SecurityGrade {
            switch self {
            case .yes: return .high
            case .no: return .low
            }
        }
    }

    enum SecurityGrade {
        case low
        case medium
        case high
    }

    enum SecurityType {
        case privacy
        case issuance
        case confiscationResistance
        case censorshipResistance

        var title: String {
            switch self {
            case .privacy: return "coin_page.security_parameters.privacy".localized
            case .issuance: return "coin_page.security_parameters.issuance".localized
            case .confiscationResistance: return "coin_page.security_parameters.confiscation_resistance".localized
            case .censorshipResistance: return "coin_page.security_parameters.censorship_resistance".localized
            }
        }
    }

    struct ChartViewItem {
        let value: String?
        let diff: String
        let diffColor: UIColor
        let chartData: ChartData?
        let chartTrend: MovementTrend
    }

    enum ChartPreviewValuePostfix {
    case currency
    case coin
    case noPostfix
    }

}

extension ChartData {

    static var placeholder: ChartData {
        let chartItems = [
            ChartItem(timestamp: 100).added(name: .rate, value: 2),
            ChartItem(timestamp: 200).added(name: .rate, value: 2),
            ChartItem(timestamp: 300).added(name: .rate, value: 1),
            ChartItem(timestamp: 400).added(name: .rate, value: 3),
            ChartItem(timestamp: 500).added(name: .rate, value: 2),
            ChartItem(timestamp: 600).added(name: .rate, value: 2)
        ]
        return ChartData(items: chartItems, startTimestamp: 100, endTimestamp: 600)
    }

}