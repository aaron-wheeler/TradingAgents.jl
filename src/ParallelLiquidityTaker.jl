"""
    PLT_run(num_traders::Int, num_assets::Int,
            parameters::Tuple{String, String, StepRangeLen{Float64}, StepRangeLen{Int}, Int, Int},
            server_info::Tuple{String, String};
            print_msg:Bool=false)

Simulate zero-intelligence liquidity takers in parallel. To operate these agents in
parallel, the `Distributed` package is used. This function must be called after
`addprocs(n)` has been called, where `n` is the number of workers to be used.

# Arguments
- `num_traders::Int`: the number of liquidity takers to simulate
- `num_assets::Int`: the number of available assets for the agents to trade
- `parameters::Tuple{String, String, StepRangeLen{Float64}, StepRangeLen{Int}, Int, Int}`: a tuple
    of parameters for the simulation. The tuple is composed of the following elements:
    - `username::String`: the username to be used for the brokerage account
    - `password::String`: the password to be used for the brokerage account
    - `init_cash_range::StepRangeLen{Float64}`: the range of initial cash values for the
        liquidity takers. E.g., `init_cash_range = 10000.0:0.01:30000.0` defines a
        possible cash balance anywhere between \\\$10,000.00 and \\\$30,000.00.
    - `init_shares_range::StepRangeLen{Int}`: the range of initial share holdings for the
        liquidity takers. E.g., `init_shares_range = 0:1:120` defines a possible share
        holding (of each available asset) anywhere between 0 shares and 120 shares.
    - `trade_freq::Int`: the average number of seconds between trades for each liquidity
        taker. E.g., `trade_freq = 720` means that each liquidity taker will trade
        approximately once every 720 seconds (12 minutes).
    - `num_MM::Int`: the number of reserved ids set aside for non-brokerage users (e.g.,
        market makers)
- `server_info::Tuple{String, String}`: a tuple of server information for
    connecting to the brokerage. The tuple is composed of the following elements:
    - `host_ip_address::String`: the IP address of the brokerage server
    - `port::String`: the port number of the brokerage server

# Keywords
- `print_msg::Bool=false`: whether or not to print messages to the console
"""
function PLT_run(num_traders, num_assets, parameters, server_info; print_msg=false)

    # unpack parameters
    username, password, init_cash_range, init_shares_range, trade_freq, num_MM = parameters
    host_ip_address, port = server_info
    print_msg == true ? println("Number of workers = ", nprocs()) : nothing

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    @everywhere Client.SERVER[] = $url
    @everywhere Client.createUser($username, $password)
    @everywhere user = Client.loginUser($username, $password)

    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()
 
    # initialize traders
    init_several_traders(num_traders, "Liquidity Taker", init_cash_range, init_shares_range)

    # preallocate trading data structures 
    assets = zeros(Int64, num_assets)
    stock_prices = zeros(Float64, num_assets)

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(LiquidityTaker) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(LiquidityTaker) Initiating trade sequence now."
    while Dates.now() < market_close

        @sync @distributed for i in 1:num_traders

            # probabilistic activation of traders
            if rand() < (1/trade_freq)

                # get personal details of activated agent
                print_msg == true ? println("Worker $(myid()). LiquidityTaker $(i) activated.") : nothing
                id = i + num_MM
                risky_wealth, assets, stock_prices = get_trade_details!(id, assets, stock_prices)

                # activated agent determines fraction of wealth to allocate to risky assets
                risk_fraction = rand(Uniform())
                total_wealth = get_total_wealth(risky_wealth, id)
                risky_wealth_allocation = total_wealth * risk_fraction
                
                # determine how to distribute risky wealth across assets
                portfolio_weights = rand(Dirichlet(num_assets, 1.0))

                # distribute risky wealth
                for ticker in eachindex(portfolio_weights)

                    # determine order details
                    desired_shares = floor(Int, portfolio_weights[ticker] * (risky_wealth_allocation / stock_prices[ticker]))
                    share_amount = desired_shares - assets[ticker]

                    # submit buy or sell market order
                    if share_amount < 0
                        fill_amount = abs(share_amount)
                        print_msg == true ? println("(PLT) SELL: trader = $(id), size = $(fill_amount), ticker = $(ticker), worker $(myid()).") : nothing
                        Client.placeMarketOrder(ticker,"SELL_ORDER",fill_amount,id)
                    elseif share_amount > 0
                        fill_amount = share_amount
                        print_msg == true ? println("(PLT) BUY: trader = $(id), size = $(fill_amount), ticker = $(ticker), worker $(myid()).") : nothing
                        Client.placeMarketOrder(ticker,"BUY_ORDER",fill_amount,id)
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
    @info "(LiquidityTaker) Trade sequence complete."
end