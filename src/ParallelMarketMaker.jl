"""
    PMM_run(...)

Simulate random market-making agent activity in "parallel" (asynchronous tasks).

# Arguments
- ...

# Keywords
- 

# Returns
- 

# References
- 
"""
function PMM_run(num_agents, num_assets, parameters, server_info; collect_data = false, print_msg=false)

    # unpack parameters
    ϵ_min,ϵ_max,unit_trade_size,trade_freq = parameters
    host_ip_address, port, username, password = server_info

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    Client.SERVER[] = url
    Client.createUser(username, password)
    user = Client.loginUser(username, password)

    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()

    # instantiate agent state data structures
    cash = zeros(num_agents)
    z = zeros(Int, num_agents, num_assets)

    # preallocate trading data structures
    new_bid = [0.0 0.0 0.0]
    new_ask = [0.0 0.0 0.0]
    place_order = [false]

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(PMM) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(PMM) Initiating trade sequence now."
    while Dates.now() < market_close

        # probabilistic activation of agents
        @sync for id in 1:num_agents
            @async if rand() < (1/trade_freq)

                #----- Order Step -----#
                @sync for ticker in 1:num_assets
                    @async begin

                        # retrieve current market conditions (current mid-price and side-spread)
                        P_t, S_ref_0 = get_price_details(ticker)
                        new_bid[1] = P_t
                        new_ask[1] = P_t
                        new_bid[2] = S_ref_0
                        new_ask[2] = S_ref_0
        
                        # check variables
                        if print_msg == true
                            println("========================")
                            println("")
                            println("P_t = ", P_t)
                            println("S_ref_0 = ", S_ref_0)
                            println("z = ", z[id, ticker])
                            println("cash = ", cash[id])
                        end
        
                        #----- Pricing Policy -----#
                        # determine how far from S_ref_0 to place quote
        
                        # Set buy and sell ϵ values
                        ϵ_buy = round(rand(Uniform(ϵ_min, ϵ_max)), digits = 2)
                        ϵ_sell = round(rand(Uniform(ϵ_min, ϵ_max)), digits = 2)
                        new_bid[3] = ϵ_buy
                        new_ask[3] = ϵ_sell
        
                        # set the limit order prices
                        print_msg == true ? println("(PMM $(id)) ϵ_buy = $(ϵ_buy), ϵ_sell = $(ϵ_sell), ticker = $(ticker)") : nothing
                        P_bid = P_t - round(S_ref_0*(1 + ϵ_buy), digits=2); P_ask = P_t + round(S_ref_0*(1 + ϵ_sell), digits=2)
                        P_bid = round(P_bid, digits=2)
                        P_ask = round(P_ask, digits=2)
                        P_bid == P_ask ? place_order[1] = false : place_order[1] = true # avoid error
                        S_ref_0 <= 0.02 ? place_order[1] = false : place_order[1] = true # avoid risk of crossing book
                        
                        # post quote on ask side
                        print_msg == true && place_order[1] == true ? println("(PMM $(id)) SELL: price = $(P_ask), size = $(unit_trade_size), ticker = $(ticker).") : nothing
                        place_order[1] == true ? order = Client.provideLiquidity(ticker,"SELL_ORDER",P_ask,unit_trade_size,id) : nothing
                        
                        # post quote on bid side
                        print_msg == true && place_order[1] == true ? println("(PMM $(id)) BUY: price = $(P_bid), size = $(unit_trade_size), ticker = $(ticker).") : nothing
                        place_order[1] == true ? order = Client.provideLiquidity(ticker,"BUY_ORDER",P_bid,unit_trade_size,id) : nothing
        
                        #----- Hedging Policy -----#
                        # Determine the fraction of current inventory to hedge (by initiating offsetting trade)
        
                        # set the hedge fraction
                        x_frac = round(rand(Uniform()), digits = 2)
        
                        # execute hedge trades process
                        # TODO: make this conditional on whether or not the agent has exceeded the inventory limit
                        order_size = round(Int, (x_frac*z[id, ticker]))
                        if !iszero(order_size) && z[id, ticker] > 0

                            # positive inventory -> hedge via sell order
                            print_msg == true ? println("(PMM $(id)) Hedge sell order -> sell $(order_size) shares (ticker = $(ticker))") : nothing
                            
                            # submit sell market order
                            order = Client.hedgeTrade(ticker,"SELL_ORDER",order_size,id)
                            
                            # update inventory
                            print_msg == true ? println("(PMM $(id)) Inventory z = $(z[id, ticker]) -> z = $(z[id, ticker] - order_size) (ticker = $(ticker))") : nothing
                            z[id, ticker] -= order_size
                            
                            # update cash (not guaranteed to be accurate, temporary fix)
                            bid_price, _ = Client.getBidAsk(ticker)
                            cash[id] += order_size*bid_price
                            cash[id] = round(cash[id], digits=2)
                        elseif !iszero(order_size) && z[id, ticker] < 0

                            # negative inventory -> hedge via buy order
                            order_size = -order_size
                            print_msg == true ? println("(PMM $(id)) Hedge buy order -> buy $(order_size) shares (ticker = $(ticker))") : nothing
                            
                            # submit buy market order
                            order = Client.hedgeTrade(ticker,"BUY_ORDER",order_size,id)
                            
                            # update inventory
                            print_msg == true ? println("(PMM $(id)) Inventory z = $(z[id, ticker]) -> z = $(z[id, ticker] + order_size) (ticker = $(ticker))") : nothing
                            z[id, ticker] += order_size
                            
                            # update cash (not guaranteed to be accurate, temporary fix)
                            _, ask_price = Client.getBidAsk(ticker)
                            cash[id] -= order_size*ask_price
                            cash[id] = round(cash[id], digits=2)
                        end

                        #----- Update Step -----#
                        # pause and reset data structures
                        sleep(1)
                        ν_new_bid = place_order[1] == true ? [unit_trade_size] : [0.0]
                        ν_new_ask = place_order[1] == true ? [unit_trade_size] : [0.0]
        
                        # retrieve data for (potentially) unfilled buy order
                        active_buy_orders = Client.getActiveBuyOrders(id, ticker)
                        for i in eachindex(active_buy_orders)

                            # retrieve order
                            unfilled_buy = (active_buy_orders[i])[2]

                            # cancel unfilled order
                            cancel_order = Client.cancelQuote(ticker,unfilled_buy.orderid,"BUY_ORDER",unfilled_buy.price,id)
                            
                            # store data
                            ν_new_bid[1] = unit_trade_size - unfilled_buy.size
                        end
        
                        # retrieve data for (potentially) unfilled sell order
                        active_sell_orders = Client.getActiveSellOrders(id, ticker)
                        for i in eachindex(active_sell_orders)

                            # retrieve order
                            unfilled_sell = (active_sell_orders[i])[2]

                            # cancel unfilled order
                            cancel_order = Client.cancelQuote(ticker,unfilled_sell.orderid,"SELL_ORDER",unfilled_sell.price,id)
                            
                            # store data
                            ν_new_ask[1] = unit_trade_size - unfilled_sell.size
                        end
        
                        # adjust cash and inventory
                        cash[id], z[id, ticker] = update_init_cash_inventory(cash[id], z[id, ticker], P_t, S_ref_0, ν_new_bid,
                                                        new_bid[3], ν_new_ask, new_ask[3])
                    end
                end
            end
        end

        # check stopping condition
        if Dates.now() > market_close
            break
        end
    end
    @info "(PMM) Trade sequence complete."

    # data collection
    if collect_data == true

        # initialize DataFrame
        cash_inv_df = DataFrame()

        # construct column for agent ids
        cash_inv_df.id = 1:num_agents

        # construct column for final agent cash
        cash_inv_df.cash = cash

        # construct column for final agent inventory
        for ticker in 1:num_assets
            cash_inv_df[!, "z_$(ticker)"] = z[:, ticker]
        end

        # create save path
        cash_inv_savepath = mkpath("../../Data/ABMs/TradingAgents/cash_inv")

        # save data
        CSV.write("$(cash_inv_savepath)/PMM_cash_inv_df.csv", cash_inv_df)
    end
end