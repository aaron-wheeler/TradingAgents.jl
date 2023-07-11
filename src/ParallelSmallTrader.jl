"""
    PST_run(num_traders::Int, num_assets::Int, parameters::Tuple{...},
            server_info::Tuple{...}; print_msg:Bool=false)

Simulate small zero-intelligence traders in parallel.

# Arguments
- `num_traders::Int`: the number of small traders to simulate
- `num_assets::Int`: the number of available assets for the agents to trade
- ...

# Keywords
- 

# Returns
- 

# References
- 
"""
function PST_run(num_traders, num_assets, parameters, server_info; print_msg=false)
    # unpack parameters
    username, password, init_cash_range, init_shares_range, trade_freq, num_MM = parameters
    host_ip_address, port = server_info
    println("Number of workers = ", nprocs()) # should be multiple

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    @everywhere Client.SERVER[] = $url
    @everywhere Client.createUser($username, $password)
    @everywhere user = Client.loginUser($username, $password)

    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()
 
    # initialize traders
    init_traders(num_traders, "SmallTrader", init_cash_range, init_shares_range, num_assets)

    # prepare recyclable trading vectors
    assets = zeros(Int64, num_assets)
    stock_prices = zeros(Float64, num_assets)

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(SmallTrader) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(SmallTrader) Initiating trade sequence now."
    while Dates.now() < market_close
        @sync @distributed for i in 1:num_traders
            # probabilistic activation of traders
            if rand() < (1/trade_freq)
                # determine new risky wealth
                println("Worker $(myid()). SmallTrader $(i) makes trade.")
                id = i + num_MM
                risk_fraction = rand(Uniform())

                # risky_wealth, assets, stock_prices = get_trade_details!(id, assets, stock_prices)
                println("url = ", Client.SERVER[])
                holdings = Client.getHoldings(id)
                # get shares in ticker-based sequence
                shares = values(holdings)
                risky_wealth = 0.0
                for i in eachindex(shares)
                    stock_prices[i] = Client.getMidPrice(i)
                    assets[i] = shares[i]
                    risky_wealth += assets[i] * stock_prices[i]
                end

                total_wealth = get_total_wealth(risky_wealth, id)
                risky_wealth_allocation = total_wealth * risk_fraction
                
                # place orders
                st_pick_stocks(num_assets, risky_wealth_allocation, assets, stock_prices, id, print_msg)
            end
        end
        # check early exit condition
        if Dates.now() > market_close
            break
        end
        sleep(1) # wait 1 second
    end
    @info "(SmallTrader) Trade sequence complete."
end

function st_pick_stocks(num_assets, risky_wealth_allocation, assets, stock_prices, id, print_msg)
    # determine portfolio weights
    portfolio_weights = rand(Dirichlet(num_assets, 1.0))
    for i in eachindex(portfolio_weights)
        ticker = i
        desired_shares = floor(Int, portfolio_weights[i] * (risky_wealth_allocation / stock_prices[i]))
        share_amount = desired_shares - assets[i]
        st_place_order(ticker, share_amount, id, print_msg)
    end
end

function st_place_order(ticker, share_amount, id, print_msg)
    if share_amount < 0
        fill_amount = abs(share_amount)
        print_msg == true ? println("SELL: SmallTrader = $(id), size = $(fill_amount), ticker = $(ticker), worker $(myid()).") : nothing
        # Client.placeMarketOrder(ticker,"SELL_ORDER",fill_amount,id)
    elseif share_amount > 0
        fill_amount = share_amount
        print_msg == true ? println("BUY: SmallTrader = $(id), size = $(fill_amount), ticker = $(ticker), worker $(myid()).") : nothing
        # Client.placeMarketOrder(ticker,"BUY_ORDER",fill_amount,id)
    end
end