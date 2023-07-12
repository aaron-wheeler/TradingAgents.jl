"""
    PLP_run(num_traders::Int, num_assets::Int, parameters::Tuple{...},
            server_info::Tuple{...}; tick_size::Float64=0.01,
            lvl::Float64=1.03, print_msg:Bool=false)

Simulate zero-intelligence liquidity providers in parallel.

# Arguments
- `num_traders::Int`: the number of liquidity providers to simulate
- `num_assets::Int`: the number of available assets for the agents to trade


# Keywords
- 

# Returns
- 

# References
- 
"""
function PLP_run(num_traders, num_assets, parameters, server_info; tick_size=0.01, lvl=1.03, print_msg=false)

    # unpack parameters
    init_cash_range, init_shares_range, trade_freq, num_ids = parameters
    host_ip_address, port, username, password = server_info
    println("Number of workers = ", nprocs()) # should be multiple

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    @everywhere Client.SERVER[] = $url
    @everywhere Client.createUser($username, $password)
    @everywhere user = Client.loginUser($username, $password)
 
    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()

    # initialize traders
    init_traders(num_traders, "Liquidity Provider", init_cash_range, init_shares_range, num_assets)

    # preallocate data structures 
    assets = zeros(Int64, num_assets) # ticker-indexed vector of each asset share count
    bid_prices = zeros(Float64, num_assets)
    ask_prices = zeros(Float64, num_assets)
    stock_prices = zeros(Float64, num_assets) # mid-price
    fundamental_values = zeros(Float64, num_assets)

    # initialize price history
    price_series = Vector{Vector{Float64}}()
    for i in 1:num_assets
        series_i = Float64[]
        push!(price_series, series_i)
    end

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(LiquidityProvider) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(LiquidityProvider) Initiating trade sequence now."
    while Dates.now() < market_close

        for i in 1:num_assets
            # retrieve new price history
            price_list = Client.getPriceSeries(i)
            price_series[i] = price_list

            # query prices
            bid_prices[i], ask_prices[i] = Client.getBidAsk(i)
            stock_prices[i] = round(((ask_prices[i] + bid_prices[i]) / 2.0); digits=2) # current mid_price
        end

        # for each activated agent, carry out order placement procedure
        @sync @distributed for agent in 1:num_traders

            # probabilistic activation of traders
            if rand() < (1/trade_freq)

                # get personal details of activated agent
                id = agent + num_ids
                assets, cash = get_agent_details!(assets, id)
                println("Worker $(myid()). LiquidityProvider $(id) activated.")

                # activated agent percieves fundamental values
                for i in eachindex(assets)

                    # test
                    println("bid_prices[$(i)] = $(bid_prices[i])")

                    # compute volatility estimate
                    if length(price_series[i]) >= 20
                        σ = max(0.10, compute_volatility(price_series[i]))
                    else
                        σ = 0.10
                    end

                    # compute agent-specific fundamental value estimates
                    deviation = rand(Normal(0, σ)) # make Uniform?
                    fundamental_values[i] = round(max(0, (stock_prices[i] * (1 + deviation))), digits=2)
                end

                # activated agent sells overpriced stocks in their portfolio
                for i in eachindex(assets)
                    # if assets[i] > 0 && stock_prices[i] > (fundamental_values[i] * lvl)
                    if assets[i] > 0 && stock_prices[i] > fundamental_values[i]

                        # determine order details
                        ticker = i
                        best_ask = ask_prices[ticker]
                        mid_ask_spread = best_ask - stock_prices[i]
                        value_arbitrage = stock_prices[i] - fundamental_values[i]
                        ask_price = round((stock_prices[i] + tick_size + mid_ask_spread/value_arbitrage), digits=2)
                        limit_size = assets[i] # sell off entire stake

                        # submit order
                        print_msg == true ? println("(LP) SELL: trader = $(id), price = $(ask_price), size = $(limit_size), ticker = $(ticker), worker $(myid()).") : nothing
                        # sell_order = Client.placeLimitOrder(ticker,"SELL_ORDER",ask_price,limit_size,id)
                    end
                end

                # activated agent buys underpriced stocks with excess cash
                if any(cash .> stock_prices)

                    # determine which asset to buy
                    most_profitable_val = 0
                    most_profitable_idx = 0
                    for i in eachindex(stock_prices)
                        if cash > stock_prices[i]
                            value_arbitrage = fundamental_values[i] - stock_prices[i]
                            most_profitable_idx = value_arbitrage > most_profitable_val ? i : most_profitable_idx
                            most_profitable_val = value_arbitrage > most_profitable_val ? value_arbitrage : most_profitable_val
                        end
                    end

                    # execute buy order
                    # the more underpriced, the closer the bid price is to the mid-price
                    if most_profitable_val > 0

                        # determine order details
                        ticker = most_profitable_idx
                        best_bid = bid_prices[ticker]
                        mid_bid_spread = stock_prices[ticker] - best_bid
                        value_arbitrage = fundamental_values[ticker] - stock_prices[ticker]
                        bid_price = round((stock_prices[ticker] - tick_size - mid_bid_spread/value_arbitrage), digits=2)
                        limit_size = trunc(Int, cash / bid_price) # buy as much as possible

                        # submit order
                        print_msg == true ? println("(LP) BUY: trader = $(id), price = $(bid_price), size = $(limit_size), ticker = $(ticker), worker $(myid()).") : nothing
                        # buy_order = Client.placeLimitOrder(ticker,"BUY_ORDER",bid_price,limit_size,id)
                    end
                end
            end
        end

        # check early exit condition
        if Dates.now() > market_close
            break
        end

        sleep(1) # wait 1 second
    end
    @info "(LiquidityProvider) Trade sequence complete."
end