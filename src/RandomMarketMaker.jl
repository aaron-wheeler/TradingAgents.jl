#=
    Deprecated in favor of ParallelMarketMaker.jl
=#

function RandomMM_run(ticker, parameters, init_conditions, server_info; collect_data = false)
    # unpack parameters
    id,ϵ_min,ϵ_max,inventory_limit,unit_trade_size,trade_freq = parameters
    cash, z = init_conditions # dynamic variables
    host_ip_address, port, username, password = server_info

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    Client.SERVER[] = url
    Client.createUser(username, password)
    user = Client.loginUser(username, password)

    # retrieve market open/close times
    market_open, market_close = Client.getMarketSchedule()

    # preallocate data structures and variables
    cash_data = Float64[]
    inventory_data = Float64[]
    new_bid = [0.0 0.0 0.0]
    new_ask = [0.0 0.0 0.0]

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(Random MM) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(Random MM) Initiating trade sequence now."
    while Dates.now() < market_close
        # check stopping condition
        if Dates.now() > market_close
            break
        end

        # retrieve current market conditions (current mid-price and side-spread)
        P_t, S_ref_0 = get_price_details(ticker)
        new_bid[1] = P_t
        new_ask[1] = P_t
        new_bid[2] = S_ref_0
        new_ask[2] = S_ref_0

        # check variables
        println("========================")
        println("")
        println("P_t = ", P_t)
        println("S_ref_0 = ", S_ref_0)
        println("z = ", z)
        println("cash = ", cash)

        #----- Pricing Policy -----#
        # determine how far from S_ref_0 to place quote

        # Set buy and sell ϵ values
        ϵ_buy = round(rand(Uniform(ϵ_min, ϵ_max)), digits = 2)
        ϵ_sell = round(rand(Uniform(ϵ_min, ϵ_max)), digits = 2)
        new_bid[3] = ϵ_buy
        new_ask[3] = ϵ_sell

        # execute actions (submit quotes)
        println("ϵ_buy = $(ϵ_buy), ϵ_sell = $(ϵ_sell)")
        P_bid = P_t - round(S_ref_0*(1 + ϵ_buy), digits=2); P_ask = P_t + round(S_ref_0*(1 + ϵ_sell), digits=2)
        P_bid = round(P_bid, digits=2)
        P_ask = round(P_ask, digits=2)
        P_bid == P_ask ? continue : nothing # avoid error
        # SUBMIT QUOTES
        # post ask quote
        println("SELL: price = $(P_ask), size = $(unit_trade_size).")
        order = Client.provideLiquidity(ticker,"SELL_ORDER",P_ask,unit_trade_size,id)
        # post bid quote
        println("BUY: price = $(P_bid), size = $(unit_trade_size).")
        order = Client.provideLiquidity(ticker,"BUY_ORDER",P_bid,unit_trade_size,id)

        #----- Hedging Policy -----#
        # Determine the fraction of current inventory to hedge (by initiating offsetting trade)

        # set the hedge fraction
        x_frac = round(rand(Uniform()), digits = 2)

        # execute actions (submit hedge trades)
        order_size = round(Int, (x_frac*z))
        if !iszero(order_size) && z > 0
            # positive inventory -> hedge via sell order
            println("Hedge sell order -> sell $(order_size) shares")
            # SUBMIT SELL MARKET ORDER
            order = Client.hedgeTrade(ticker,"SELL_ORDER",order_size,id)
            # UPDATE z
            println("Inventory z = $(z) -> z = $(z - order_size)")
            z -= order_size
            # UPDATE cash (not accurate, temporary fix)
            bid_price, _ = Client.getBidAsk(ticker)
            cash += order_size*bid_price
            cash = round(cash, digits=2)
        elseif !iszero(order_size) && z < 0
            # negative inventory -> hedge via buy order
            order_size = -order_size
            println("Hedge buy order -> buy $(order_size) shares")
            # SUBMIT BUY MARKET ORDER
            order = Client.hedgeTrade(ticker,"BUY_ORDER",order_size,id)
            # UPDATE z
            println("Inventory z = $(z) -> z = $(z + order_size)")
            z += order_size
            # UPDATE cash (not accurate, temporary fix)
            _, ask_price = Client.getBidAsk(ticker)
            cash -= order_size*ask_price
            cash = round(cash, digits=2)
        end

        # wait 'trade_freq' seconds and reset data structures
        sleep(trade_freq)
        ν_new_bid = [unit_trade_size]
        ν_new_ask = [unit_trade_size]

        #----- Update Step -----#

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
        cash, z = update_init_cash_inventory(cash, z, P_t, S_ref_0, ν_new_bid,
                                        new_bid[3], ν_new_ask, new_ask[3])

        # compute and store cash and inventory data
        if collect_data == true
            push!(cash_data, cash)
            push!(inventory_data, z)
        end
    end
    @info "(Random MM) Trade sequence complete."

    # clear inventory
    order_size = z
    if !iszero(order_size) && z > 0
        # positive inventory -> hedge via sell order
        println("Hedge sell order -> sell $(order_size) shares")
        # SUBMIT SELL MARKET ORDER
        order = Client.hedgeTrade(ticker,"SELL_ORDER",order_size,id)
        # UPDATE z
        println("Inventory z = $(z) -> z = $(z - order_size)")
        z -= order_size
        # UPDATE cash (not accurate, temporary fix)
        bid_price, _ = Client.getBidAsk(ticker)
        cash += order_size*bid_price
        cash = round(cash, digits=2)
        println("profit = ", cash)
    elseif !iszero(order_size) && z < 0
        # negative inventory -> hedge via buy order
        order_size = -order_size
        println("Hedge buy order -> buy $(order_size) shares")
        # SUBMIT BUY MARKET ORDER
        order = Client.hedgeTrade(ticker,"BUY_ORDER",order_size,id)
        # UPDATE z
        println("Inventory z = $(z) -> z = $(z + order_size)")
        z += order_size
        # UPDATE cash (not accurate, temporary fix)
        _, ask_price = Client.getBidAsk(ticker)
        cash -= order_size*ask_price
        cash = round(cash, digits=2)
        println("profit = ", cash)
    else
        println("profit = ", cash)
    end

    # compute and store cash and inventory data
    if collect_data == true
        push!(cash_data, cash)
        push!(inventory_data, z)
    end

    # Data collection
    if collect_data == true
        # for cash and inventory - prepare tabular dataset
        cash_inv_data = DataFrame(cash_dt = cash_data, inv_dt = inventory_data)
        # for cash and inventory - create save path
        cash_inv_savepath = mkpath("../../Data/ABMs/Exchange/cash_inv")
        # for cash and inventory - save data
        CSV.write("$(cash_inv_savepath)/random_cash_inv_data_id$(id).csv", cash_inv_data)
    end
end