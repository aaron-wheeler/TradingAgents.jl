"""
    PLP_run(num_traders::Int, num_assets::Int,
            parameters::Tuple{StepRangeLen{Float64}, StepRangeLen{Int}, Int, Int},
            server_info::Tuple{String, String, String, String};
            print_msg:Bool=false)

Simulate zero-intelligence liquidity providers in parallel. To operate these agents in
parallel, the `Distributed` package is used. This function must be called after
`addprocs(n)` has been called, where `n` is the number of workers to be used.

# Arguments
- `num_traders::Int`: the number of liquidity providers to simulate
- `num_assets::Int`: the number of available assets for the agents to trade
- `parameters::Tuple{StepRangeLen{Float64}, StepRangeLen{Int}, Int, Int}`: a tuple
    of parameters for the simulation. The tuple is composed of the following elements:
    - `init_cash_range::StepRangeLen{Float64}`: the range of initial cash values for the
        liquidity providers. E.g., `init_cash_range = 10000.0:0.01:30000.0` defines a
        possible cash balance anywhere between $10,000.00 and $30,000.00.
    - `init_shares_range::StepRangeLen{Int}`: the range of initial share holdings for the
        liquidity providers. E.g., `init_shares_range = 0:1:120` defines a possible share
        holding (of each available asset) anywhere between 0 shares and 120 shares.
    - `trade_freq::Int`: the average number of seconds between trades for each liquidity
        provider. E.g., `trade_freq = 720` means that each liquidity provider will trade
        approximately once every 720 seconds (12 minutes).
    - `num_ids::Int`: the number of reserved ids set aside for all other agents in the
        simulation (e.g., liquidity takers and market makers)
- `server_info::Tuple{String, String, String, String}`: a tuple of server information for
    connecting to the brokerage. The tuple is composed of the following elements:
    - `host_ip_address::String`: the IP address of the brokerage server
    - `port::String`: the port number of the brokerage server
    - `username::String`: the username to be used for the brokerage account
    - `password::String`: the password to be used for the brokerage account

# Keywords
- `print_msg::Bool=false`: whether or not to print messages to the console
"""
function PLP_run(num_traders, num_assets, parameters, server_info; print_msg=false)

    # unpack parameters
    init_cash_range, init_shares_range, trade_freq, num_ids = parameters
    host_ip_address, port, username, password = server_info
    print_msg == true ? println("Number of workers = ", nprocs()) : nothing

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    @everywhere Client.SERVER[] = $url
    @everywhere Client.createUser($username, $password)
    @everywhere user = Client.loginUser($username, $password)
 
    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()

    # initialize traders
    init_several_traders(num_traders, "Liquidity Provider", init_cash_range, init_shares_range)

    # preallocate trading data structures 
    assets = zeros(Int64, num_assets)
    bid_price = zeros(Float64, num_assets)
    ask_price = zeros(Float64, num_assets)
    stock_price = zeros(Float64, num_assets)
    price_draw = zeros(Float64, num_assets)
    eligible_bid = zeros(Int, num_assets)

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

        # update observable market variables
        for i in 1:num_assets

            # retrieve new price history
            price_list = Client.getPriceSeries(i)
            price_series[i] = price_list

            # query prices
            bid_price[i], ask_price[i] = Client.getBidAsk(i)
            stock_price[i] = round(((ask_price[i] + bid_price[i]) / 2.0); digits=2) # current mid-price
        end

        # for each activated agent, carry out order placement procedure
        @sync @distributed for agent in 1:num_traders

            # probabilistic activation of traders
            if rand() < (1/trade_freq)

                # get personal details of activated agent
                id = agent + num_ids
                assets, cash = get_agent_details!(assets, id)
                print_msg == true ? println("Worker $(myid()). LiquidityProvider $(id) activated.") : nothing

                # activated agent computes limit price for each asset
                for i in eachindex(assets)

                    # compute volatility estimate
                    if length(price_series[i]) >= 20
                        σ = max(0.10, compute_volatility(price_series[i]))
                    else
                        σ = 0.10 # default volatility value
                    end

                    # draw limit price from probability distribution
                    deviation = rand(Normal(0, σ)) # make this uniform distribution?
                    price_draw[i] = round(max(0, (stock_price[i] * (1 + deviation))), digits=2)
                end

                # activated agent sells off assets from their portfolio
                for ticker in eachindex(assets)
                    if assets[ticker] > 0 && stock_price[ticker] < price_draw[ticker]

                        # determine order details
                        limit_price = max(ask_price[ticker], price_draw[ticker])
                        limit_size = round(Int, rand(Uniform())*assets[ticker]) # sell off partial stake

                        # submit order
                        print_msg == true && limit_size > 0 ? println("(PLP) SELL: trader = $(id), price = $(limit_price), size = $(limit_size), ticker = $(ticker), worker $(myid()).") : nothing
                        limit_size > 0 ? Client.placeLimitOrder(ticker,"SELL_ORDER",limit_price,limit_size,id) : nothing
                    end
                end

                # activated agent buys assets with excess cash
                if any(cash .> stock_price)

                    # determine which assets are eligible for purchase
                    for i in eachindex(stock_price)
                        eligible_bid[i] = cash > price_draw[i] && price_draw[i] < stock_price[i] ? 1 : 0
                    end

                    # determine how to distribute cash across eligible assets
                    num_eligible_buys = sum(eligible_bid)
                    cash_weights = num_eligible_buys > 0 ? rand(Dirichlet(num_eligible_buys, 1.0)) : [0.0]
                    
                    # submit orders for each eligible asset
                    cash_idx = 1
                    for ticker in eachindex(stock_price)
                        if eligible_bid[ticker] == 1

                            # determine order details
                            limit_price = min(bid_price[ticker], price_draw[ticker])
                            limit_size = floor(Int, cash_weights[cash_idx] * (cash / limit_price))
                            cash_idx += 1
                            limit_size > 0 ? nothing : continue # skip if no cash to buy

                            # submit order
                            print_msg == true ? println("(PLP) BUY: trader = $(id), price = $(limit_price), size = $(limit_size), ticker = $(ticker), worker $(myid()).") : nothing
                            Client.placeLimitOrder(ticker,"BUY_ORDER",limit_price,limit_size,id)
                        end
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