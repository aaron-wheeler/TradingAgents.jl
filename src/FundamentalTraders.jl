"""
    FT_run(num_traders::Int, num_assets::Int, market_open::DateTime,
            market_close::DateTime, parameters::Tuple{...},
            server_info::Tuple{...}; tick_size::Float64=0.01, lvl::Float64=1.03, print_msg:Bool=false)

Simulate fundamental trading agent activity.

# Arguments
- `num_traders::Int`: the number of fundamental traders to simulate
- `num_assets::Int`: the number of available assets for the agents to trade


# Keywords
- 

# Returns
- 

# References
- 
"""
function FT_run(num_traders, num_assets, market_open, market_close, parameters, server_info; tick_size=0.01, lvl=1.03, print_msg=false)

    # unpack parameters
    init_cash_range, init_shares_range, prob_wait, trade_freq, num_ids = parameters
    host_ip_address, port, username, password = server_info

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    Client.SERVER[] = url
    Client.createUser(username, password)
    user = Client.loginUser(username, password)
 
    # initialize traders
    init_traders(num_traders, init_cash_range, init_shares_range, num_assets)
    
    # instantiate Pareto distribution for trader activation
    granularity = (8.0 - 1.0)/num_traders
    time = 1.01:granularity:8.01
    prob_activation = (pdf.(Pareto(1,1), time))[1:num_traders]

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
        @info "(FundamentalTraders) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(FundamentalTraders) Initiating trade sequence now."
    while Dates.now() < market_close

        # probabilistic activation of traders
        trade_draw = (1 - rand(prob_activation)) * num_traders
        agents_to_trade = ceil(Int, trade_draw)
        trade_queue = collect(Int, agents_to_trade:num_traders)
        shuffle!(trade_queue)

        # retrieve new price history
        for i in 1:num_assets
            price_list = Client.getPriceSeries(i)
            price_series[i] = price_list
        end
        # println(price_series)

        # for each activated agent, carry out order placement procedure
        for agent in eachindex(trade_queue)

            # probabilistically ...
            if rand() <= prob_wait
                # ..wait 'trade_freq' seconds
                sleep(trade_freq)
            end

            # get personal details of activated agent
            id = trade_queue[agent] + num_ids
            assets, cash = get_agent_details!(assets, id)

            # activated agent percieves fundamental values
            for i in eachindex(assets)

                # query prices
                bid_prices[i], ask_prices[i] = Client.getBidAsk(i)
                stock_prices[i] = round(((ask_prices[i] + bid_prices[i]) / 2.0); digits=2) # current mid_price

                # compute volatility estimate
                if length(price_series[i]) >= 20
                    σ = max(0.10, compute_volatility(price_series[i]))
                else
                    σ = 0.10
                end

                # compute agent-specific fundamental value estimates
                deviation = rand(Normal(0, σ))
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
                    print_msg == true ? println("(FT) SELL: trader = $(id), price = $(ask_price), size = $(limit_size), ticker = $(ticker).") : nothing
                    sell_order = Client.placeLimitOrder(ticker,"SELL_ORDER",ask_price,limit_size,id)
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
                    print_msg == true ? println("(FT) BUY: trader = $(id), price = $(bid_price), size = $(limit_size), ticker = $(ticker).") : nothing
                    buy_order = Client.placeLimitOrder(ticker,"BUY_ORDER",bid_price,limit_size,id)
                end
            end
            
            # check early exit condition
            if Dates.now() > market_close
                break
            end
        end
    end
    @info "(FundamentalTraders) Trade sequence complete."
end