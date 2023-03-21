function init_traders(num_traders, init_cash_range, init_shares_range, num_assets)
    for i in 1:num_traders
        name = "Trader $(i)"
        cash = rand(init_cash_range)
        holdings = Dict{Int64, Int64}()
        for ticker in 1:num_assets
            init_shares = rand(init_shares_range)
            holdings[ticker] = init_shares
        end
        portfolio = Client.createPortfolio(name, cash, holdings)
    end
end

# function get_trade_details!(id, assets, stock_prices)
#     holdings = Client.getHoldings(id)
#     # get shares in ticker-based sequence
#     shares = values(holdings)
#     risky_wealth = 0.0
#     for i in eachindex(shares)
#         stock_prices[i] = Client.getMidPrice(i)
#         assets[i] = shares[i]
#         risky_wealth += assets[i] * stock_prices[i]
#     end
#     return risky_wealth, assets, stock_prices
# end

# function get_total_wealth(risky_wealth, id)
#     total_wealth = risky_wealth + Client.getCash(id)
#     return total_wealth
# end

function get_agent_details!(assets, id)

    # get agent shares count and store it in ticker-indexed vector form -
    holdings = Client.getHoldings(id)
    shares = values(holdings)
    for i in eachindex(shares)
        assets[i] = shares[i]
    end

    # get agent cash -
    cash = Client.getCash(id)

    # return -
    return assets, cash
end

function compute_volatility(price_series, lookback_period)
    
    # compute the volatility σ -
    log_returns = diff(log.(price_series[lookback_period:end,1])) # close-to-close returns
    sum_returns += sum(log_returns)
    mean_return = sum(log_returns) / length(log_returns)
    return_variance = sum((log_returns .- mean_return).^2) / (length(log_returns) - 1)
    σ_new = sqrt(return_variance) # volatility

    # return -
    return σ_new
end