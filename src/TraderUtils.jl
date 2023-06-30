function init_traders(num_traders, trader_label, init_cash_range, init_shares_range, num_assets)
    for i in 1:num_traders
        name = "$(trader_label) $(i)"
        cash = rand(init_cash_range)
        holdings = Dict{Int64, Int64}()
        for ticker in 1:num_assets
            init_shares = rand(init_shares_range)
            holdings[ticker] = init_shares
        end
        portfolio = Client.createPortfolio(name, cash, holdings)
    end
end

function get_trade_details!(id, assets, stock_prices)
    holdings = Client.getHoldings(id)
    # get shares in ticker-based sequence
    shares = values(holdings)
    risky_wealth = 0.0
    for i in eachindex(shares)
        stock_prices[i] = Client.getMidPrice(i)
        assets[i] = shares[i]
        risky_wealth += assets[i] * stock_prices[i]
    end
    return risky_wealth, assets, stock_prices
end

function get_total_wealth(risky_wealth, id)
    total_wealth = risky_wealth + Client.getCash(id)
    return total_wealth
end

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

function compute_volatility(price_series)
    
    # compute the volatility σ -
    log_returns = diff(log.(price_series[:,1])) # close-to-close returns
    mean_return = sum(log_returns) / length(log_returns)
    return_variance = sum((log_returns .- mean_return).^2) / (length(log_returns) - 1)
    σ_new = sqrt(return_variance) # volatility

    # return -
    return σ_new
end

# ====================================================================== #
# #----- MM Utility functions -----#

function update_init_cash_inventory(cash, z, P_last, S_ref_last, bid_ν_ϵ_t,
                bid_ϵ_vals_t, ask_ν_ϵ_t, ask_ϵ_vals_t)
    # balance debts
    cash -= sum(bid_ν_ϵ_t .* round.(P_last .- (S_ref_last .* (1 .+ bid_ϵ_vals_t)), digits=2))
    z += sum(bid_ν_ϵ_t)

    # balance credits
    cash += sum(ask_ν_ϵ_t .* round.(P_last .+ (S_ref_last .* (1 .+ ask_ϵ_vals_t)), digits=2))
    z -= sum(ask_ν_ϵ_t)

    return round(cash, digits=2), z
end

function get_price_details(ticker)
    bid_price, ask_price = Client.getBidAsk(ticker)
    mid_price = round(((ask_price + bid_price) / 2.0); digits=2) # current mid_price
    spread = ask_price - bid_price
    S_ref_0 = round((spread / 2.0), digits=2) # current best spread
    return mid_price, S_ref_0
end