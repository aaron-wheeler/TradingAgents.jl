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
function PMM_run(num_agents, num_assets, parameters, server_info; collect_all_data = false, collect_final_only = false, print_msg=false)
    # unpack parameters
    ϵ_min,ϵ_max,inventory_limit,unit_trade_size,trade_freq = parameters
    host_ip_address, port, username, password = server_info

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    Client.SERVER[] = url
    Client.createUser(username, password)
    user = Client.loginUser(username, password)

    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()

    # # TODO: instantiate plotting data structures
    # cash_data = Float64[]
    # inventory_data = Int[]

    # instantiate agent state data structures
    cash = zeros(num_agents)
    z = zeros(Int, num_agents, num_assets)

    # preallocate trading data structures
    new_bid = [0.0 0.0 0.0]
    new_ask = [0.0 0.0 0.0]

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(PMM) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(PMM) Initiating trade sequence now."
    while Dates.now() < market_close
        # check stopping condition
        if Dates.now() > market_close
            break
        end

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
        
                        # execute actions (submit quotes)
                        print_msg == true ? println("(PMM $(id)) ϵ_buy = $(ϵ_buy), ϵ_sell = $(ϵ_sell), ticker = $(ticker)") : nothing
                        P_bid = P_t - round(S_ref_0*(1 + ϵ_buy), digits=2); P_ask = P_t + round(S_ref_0*(1 + ϵ_sell), digits=2)
                        P_bid = round(P_bid, digits=2)
                        P_ask = round(P_ask, digits=2)
                        P_bid == P_ask ? place_order = false : place_order = true # avoid error
                        ## SUBMIT QUOTES
                        # post ask quote
                        print_msg == true && place_order == true ? println("(PMM $(id)) SELL: price = $(P_ask), size = $(unit_trade_size), ticker = $(ticker).") : nothing
                    #    # place_order == true ? order = Client.provideLiquidity(ticker,"SELL_ORDER",P_ask,unit_trade_size,id) : nothing
                        # post bid quote
                        print_msg == true && place_order == true ? println("(PMM $(id)) BUY: price = $(P_bid), size = $(unit_trade_size), ticker = $(ticker).") : nothing
                    #    # place_order == true ? order = Client.provideLiquidity(ticker,"BUY_ORDER",P_bid,unit_trade_size,id) : nothing
        
                        #----- Hedging Policy -----#
                        # Determine the fraction of current inventory to hedge (by initiating offsetting trade)
        
                        # set the hedge fraction
                        x_frac = round(rand(Uniform()), digits = 2)
        
                        # execute actions (submit hedge trades)
                        # TODO: make this conditional on whether or not the agent has exceeded the inventory limit
                        order_size = round(Int, (x_frac*z[id, ticker]))
                        if !iszero(order_size) && z[id, ticker] > 0
                            # positive inventory -> hedge via sell order
                            print_msg == true ? println("(PMM $(id)) Hedge sell order -> sell $(order_size) shares (ticker = $(ticker))") : nothing
                            ## SUBMIT SELL MARKET ORDER
                        #    # order = Client.hedgeTrade(ticker,"SELL_ORDER",order_size,id)
                            # UPDATE z
                            print_msg == true ? println("(PMM $(id)) Inventory z = $(z[id, ticker]) -> z = $(z[id, ticker] - order_size) (ticker = $(ticker))") : nothing
                            z[id, ticker] -= order_size
                            # UPDATE cash (not guaranteed to be accurate, temporary fix)
                            bid_price, _ = Client.getBidAsk(ticker)
                            cash[id] += order_size*bid_price
                            cash[id] = round(cash[id], digits=2)
                        elseif !iszero(order_size) && z[id, ticker] < 0
                            # negative inventory -> hedge via buy order
                            order_size = -order_size
                            print_msg == true ? println("(PMM $(id)) Hedge buy order -> buy $(order_size) shares (ticker = $(ticker))") : nothing
                            ## SUBMIT BUY MARKET ORDER
                        #    # order = Client.hedgeTrade(ticker,"BUY_ORDER",order_size,id)
                            # UPDATE z
                            print_msg == true ? println("(PMM $(id)) Inventory z = $(z[id, ticker]) -> z = $(z[id, ticker] + order_size) (ticker = $(ticker))") : nothing
                            z[id, ticker] += order_size
                            # UPDATE cash (not guaranteed to be accurate, temporary fix)
                            _, ask_price = Client.getBidAsk(ticker)
                            cash[id] -= order_size*ask_price
                            cash[id] = round(cash[id], digits=2)
                        end

                        #----- Update Step -----#
                        # wait 1 second and reset data structures
                        sleep(1)
                        ν_new_bid = [unit_trade_size]
                        ν_new_ask = [unit_trade_size]
        
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
        
                        # # compute and store cash and inventory data
                        # if collect_all_data == true
                        #     push!(cash_data, cash[id])
                        #     push!(inventory_data, z[id, ticker])
                        # end
                    end
                end

                # #----- Update Step -----#
                # @sync for ticker in 1:num_assets
                #     @async begin
                #         # wait 1 second and reset data structures
                #         sleep(1)
                #         ν_new_bid = [unit_trade_size]
                #         ν_new_ask = [unit_trade_size]
        
                #         # retrieve data for (potentially) unfilled buy order
                #         active_buy_orders = Client.getActiveBuyOrders(id, ticker)
                #         for i in eachindex(active_buy_orders)
                #             # retrieve order
                #             unfilled_buy = (active_buy_orders[i])[2]
                #             # cancel unfilled order
                #             cancel_order = Client.cancelQuote(ticker,unfilled_buy.orderid,"BUY_ORDER",unfilled_buy.price,id)
                #             # store data
                #             ν_new_bid[1] = unit_trade_size - unfilled_buy.size
                #         end
        
                #         # retrieve data for (potentially) unfilled sell order
                #         active_sell_orders = Client.getActiveSellOrders(id, ticker)
                #         for i in eachindex(active_sell_orders)
                #             # retrieve order
                #             unfilled_sell = (active_sell_orders[i])[2]
                #             # cancel unfilled order
                #             cancel_order = Client.cancelQuote(ticker,unfilled_sell.orderid,"SELL_ORDER",unfilled_sell.price,id)
                #             # store data
                #             ν_new_ask[1] = unit_trade_size - unfilled_sell.size
                #         end
        
                #         # adjust cash and inventory
                #         cash[id], z[id, ticker] = update_init_cash_inventory(cash[id], z[id, ticker], P_t, S_ref_0, ν_new_bid,
                #                                         new_bid[3], ν_new_ask, new_ask[3])
        
                #         # # compute and store cash and inventory data
                #         # if collect_all_data == true
                #         #     push!(cash_data, cash[id])
                #         #     push!(inventory_data, z[id, ticker])
                #         # end
                #     end
                # end

                # sleep(1) # wait 1 second
            end
        end

        # #----- Order Step -----#
        # for id in 1:num_agents
        #     for ticker in 1:num_assets
        #         # retrieve current market conditions (current mid-price and side-spread)
        #         P_t, S_ref_0 = get_price_details(ticker)
        #         new_bid[1] = P_t
        #         new_ask[1] = P_t
        #         new_bid[2] = S_ref_0
        #         new_ask[2] = S_ref_0

        #         # check variables
        #         if print_msg == true
        #             println("========================")
        #             println("")
        #             println("P_t = ", P_t)
        #             println("S_ref_0 = ", S_ref_0)
        #             println("z = ", z[id, ticker])
        #             println("cash = ", cash[id])
        #         end

        #         #----- Pricing Policy -----#
        #         # determine how far from S_ref_0 to place quote

        #         # Set buy and sell ϵ values
        #         ϵ_buy = round(rand(Uniform(ϵ_min, ϵ_max)), digits = 2)
        #         ϵ_sell = round(rand(Uniform(ϵ_min, ϵ_max)), digits = 2)
        #         new_bid[3] = ϵ_buy
        #         new_ask[3] = ϵ_sell

        #         # execute actions (submit quotes)
        #         print_msg == true ? println("(PMM $(id)) ϵ_buy = $(ϵ_buy), ϵ_sell = $(ϵ_sell), ticker = $(ticker)") : nothing
        #         P_bid = P_t - round(S_ref_0*(1 + ϵ_buy), digits=2); P_ask = P_t + round(S_ref_0*(1 + ϵ_sell), digits=2)
        #         P_bid = round(P_bid, digits=2)
        #         P_ask = round(P_ask, digits=2)
        #         P_bid == P_ask ? continue : nothing # avoid error
        #         ## SUBMIT QUOTES
        #         # post ask quote
        #         print_msg == true ? println("(PMM $(id)) SELL: price = $(P_ask), size = $(unit_trade_size), ticker = $(ticker).") : nothing
        #     #    # order = Client.provideLiquidity(ticker,"SELL_ORDER",P_ask,unit_trade_size,id)
        #         # post bid quote
        #         print_msg == true ? println("(PMM $(id)) BUY: price = $(P_bid), size = $(unit_trade_size), ticker = $(ticker).") : nothing
        #     #    # order = Client.provideLiquidity(ticker,"BUY_ORDER",P_bid,unit_trade_size,id)

        #         #----- Hedging Policy -----#
        #         # Determine the fraction of current inventory to hedge (by initiating offsetting trade)

        #         # set the hedge fraction
        #         x_frac = round(rand(Uniform()), digits = 2)

        #         # execute actions (submit hedge trades)
        #         order_size = round(Int, (x_frac*z[id, ticker]))
        #         if !iszero(order_size) && z[id, ticker] > 0
        #             # positive inventory -> hedge via sell order
        #             print_msg == true ? println("(PMM $(id)) Hedge sell order -> sell $(order_size) shares (ticker = $(ticker))") : nothing
        #             ## SUBMIT SELL MARKET ORDER
        #         #    # order = Client.hedgeTrade(ticker,"SELL_ORDER",order_size,id)
        #             # UPDATE z
        #             print_msg == true ? println("(PMM $(id)) Inventory z = $(z[id, ticker]) -> z = $(z[id, ticker] - order_size) (ticker = $(ticker))") : nothing
        #             z[id, ticker] -= order_size
        #             # UPDATE cash (not guaranteed to be accurate, temporary fix)
        #             bid_price, _ = Client.getBidAsk(ticker)
        #             cash[id] += order_size*bid_price
        #             cash[id] = round(cash[id], digits=2)
        #         elseif !iszero(order_size) && z[id, ticker] < 0
        #             # negative inventory -> hedge via buy order
        #             order_size = -order_size
        #             print_msg == true ? println("(PMM $(id)) Hedge buy order -> buy $(order_size) shares (ticker = $(ticker))") : nothing
        #             ## SUBMIT BUY MARKET ORDER
        #         #    # order = Client.hedgeTrade(ticker,"BUY_ORDER",order_size,id)
        #             # UPDATE z
        #             print_msg == true ? println("(PMM $(id)) Inventory z = $(z[id, ticker]) -> z = $(z[id, ticker] + order_size) (ticker = $(ticker))") : nothing
        #             z[id, ticker] += order_size
        #             # UPDATE cash (not guaranteed to be accurate, temporary fix)
        #             _, ask_price = Client.getBidAsk(ticker)
        #             cash[id] -= order_size*ask_price
        #             cash[id] = round(cash[id], digits=2)
        #         end
        #     end
        # end

        # #----- Update Step -----#
        # for id in 1:num_agents
        #     for ticker in 1:num_assets
        #         # wait 'trade_freq' seconds and reset data structures
        #         # sleep(trade_freq)
        #         ν_new_bid = [unit_trade_size]
        #         ν_new_ask = [unit_trade_size]

        #         # retrieve data for (potentially) unfilled buy order
        #         active_buy_orders = Client.getActiveBuyOrders(id, ticker)
        #         for i in eachindex(active_buy_orders)
        #             # retrieve order
        #             unfilled_buy = (active_buy_orders[i])[2]
        #             # cancel unfilled order
        #             cancel_order = Client.cancelQuote(ticker,unfilled_buy.orderid,"BUY_ORDER",unfilled_buy.price,id)
        #             # store data
        #             ν_new_bid[1] = unit_trade_size - unfilled_buy.size
        #         end

        #         # retrieve data for (potentially) unfilled sell order
        #         active_sell_orders = Client.getActiveSellOrders(id, ticker)
        #         for i in eachindex(active_sell_orders)
        #             # retrieve order
        #             unfilled_sell = (active_sell_orders[i])[2]
        #             # cancel unfilled order
        #             cancel_order = Client.cancelQuote(ticker,unfilled_sell.orderid,"SELL_ORDER",unfilled_sell.price,id)
        #             # store data
        #             ν_new_ask[1] = unit_trade_size - unfilled_sell.size
        #         end

        #         # adjust cash and inventory
        #         cash[id], z[id, ticker] = update_init_cash_inventory(cash[id], z[id, ticker], P_t, S_ref_0, ν_new_bid,
        #                                         new_bid[3], ν_new_ask, new_ask[3])

        #         # # compute and store cash and inventory data
        #         # if collect_all_data == true
        #         #     push!(cash_data, cash[id])
        #         #     push!(inventory_data, z[id, ticker])
        #         # end
        #     end
        # end
    end
    @info "(PMM) Trade sequence complete."

    # # TODO: clear inventory
    # for id in 1:num_agents
    #     for ticker in 1:num_assets
    #         order_size = z
    #         if !iszero(order_size) && z > 0
    #             # positive inventory -> hedge via sell order
    #             println("Hedge sell order -> sell $(order_size) shares")
    #             # SUBMIT SELL MARKET ORDER
    #             order = Client.hedgeTrade(ticker,"SELL_ORDER",order_size,id)
    #             # UPDATE z
    #             println("Inventory z = $(z) -> z = $(z - order_size)")
    #             z -= order_size
    #             # UPDATE cash (not accurate, temporary fix)
    #             bid_price, _ = Client.getBidAsk(ticker)
    #             cash += order_size*bid_price
    #             cash = round(cash, digits=2)
    #             println("profit = ", cash)
    #         elseif !iszero(order_size) && z < 0
    #             # negative inventory -> hedge via buy order
    #             order_size = -order_size
    #             println("Hedge buy order -> buy $(order_size) shares")
    #             # SUBMIT BUY MARKET ORDER
    #             order = Client.hedgeTrade(ticker,"BUY_ORDER",order_size,id)
    #             # UPDATE z
    #             println("Inventory z = $(z) -> z = $(z + order_size)")
    #             z += order_size
    #             # UPDATE cash (not accurate, temporary fix)
    #             _, ask_price = Client.getBidAsk(ticker)
    #             cash -= order_size*ask_price
    #             cash = round(cash, digits=2)
    #             println("profit = ", cash)
    #         else
    #             println("profit = ", cash)
    #         end
    #     end
    # end

    # # TODO: compute and store cash and inventory data
    # if collect_all_data == true || collect_final_only == true
    #     push!(cash_data, cash)
    #     push!(inventory_data, z)
    # end

    # # TODO: Data collection
    # if collect_all_data == true || collect_final_only == true
    #     # for cash and inventory - prepare tabular dataset
    #     cash_inv_data = DataFrame(cash_dt = cash_data, inv_dt = inventory_data)
    #     # for cash and inventory - create save path
    #     cash_inv_savepath = mkpath("../../Data/ABMs/Exchange/cash_inv")
    #     # for cash and inventory - save data
    #     CSV.write("$(cash_inv_savepath)/random_cash_inv_data_id$(id).csv", cash_inv_data)
    # end
end