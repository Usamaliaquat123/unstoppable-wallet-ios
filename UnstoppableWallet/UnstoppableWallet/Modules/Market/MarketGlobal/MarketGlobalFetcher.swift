import RxSwift
import Foundation
import MarketKit
import CurrencyKit
import Chart

class MarketGlobalFetcher {
    private let marketKit: MarketKit.Kit
    private let currencyKit: CurrencyKit.Kit
    private let metricsType: MarketGlobalModule.MetricsType

    init(currencyKit: CurrencyKit.Kit, marketKit: MarketKit.Kit, metricsType: MarketGlobalModule.MetricsType) {
        self.marketKit = marketKit
        self.currencyKit = currencyKit
        self.metricsType = metricsType
    }

}

extension MarketGlobalFetcher: IMetricChartConfiguration {
    var title: String { metricsType.title }
    var description: String? { metricsType.description }
    var poweredBy: String? { "DefiLlama API" }

    var valueType: MetricChartModule.ValueType {
        .compactCurrencyValue(currencyKit.baseCurrency)
    }

}

extension MarketGlobalFetcher: IMetricChartFetcher {

    func fetchSingle(interval: HsTimePeriod) -> RxSwift.Single<[MetricChartModule.Item]> {
        marketKit
                .globalMarketPointsSingle(currencyCode: currencyKit.baseCurrency.code, timePeriod: interval)
                .map { [weak self] points in
                    let result = points.map { point -> MetricChartModule.Item in
                        let value: Decimal
                        var additional = [ChartIndicatorName: Decimal]()

                        switch self?.metricsType {
                        case .defiCap: value = point.defiMarketCap
                        case .totalMarketCap:
                            value = point.marketCap
                            additional[.dominance] = point.btcDominance
                        case .tvlInDefi: value = point.tvl
                        case .none, .volume24h: value = point.volume24h
                        }

                        return MetricChartModule.Item(value: value, indicators: additional, timestamp: point.timestamp)
                    }


                    return result
                }
    }

}
