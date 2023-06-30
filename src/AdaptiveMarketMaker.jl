# ====================================================================== #
# #----- Initialization Procedure -----#

function post_rand_quotes(ticker, num_quotes, unit_trade_size, id,
                    bid_order_ids_t, bid_ϵ_vals_t, ask_order_ids_t, ask_ϵ_vals_t)
    # send random orders
    P_t, S_ref_0 = get_price_details(ticker)
    rand_ϵ = [rand(-0.49:0.01:1.5) for _ in 1:num_quotes]
    # compute limit prices
    S_bid = S_ref_0 .* (1 .+ rand_ϵ')
    P_bid = round.(P_t .- S_bid, digits=2)
    S_ask = S_ref_0 .* (1 .+ rand_ϵ')
    P_ask = round.(P_t .+ S_ask, digits=2)
    # post quotes
    for i in 1:num_quotes
        # post ask quote
        ask_order = Client.provideLiquidity(ticker,"SELL_ORDER",P_ask[i],unit_trade_size,id,send_id=true)
        println("SELL: price = $(P_ask[i]), size = $(unit_trade_size).")
        # fill quote vector with order_id
        ask_order_ids_t[i] = ask_order

        # post bid quote
        bid_order = Client.provideLiquidity(ticker,"BUY_ORDER",P_bid[i],unit_trade_size,id,send_id=true)
        println("BUY: price = $(P_bid[i]), size = $(unit_trade_size).")
        # fill quote vector with order_id
        bid_order_ids_t[i] = bid_order
    end
    # fill quote vectors
    ask_ϵ_vals_t = rand_ϵ
    bid_ϵ_vals_t = rand_ϵ

    return P_t, S_ref_0, bid_order_ids_t, bid_ϵ_vals_t, ask_order_ids_t, ask_ϵ_vals_t
end

# #----- Incoming net flow (ν_ϵ) & normalized spread PnL (s_ϵ) mean and variance estimates -----#

# initialize Empirical Response Table
function construct_ERTable(P_last, S_ref_last, num_quotes, bid_ϵ_vals_t,
                                    bid_ν_ϵ_t, ask_ϵ_vals_t, ask_ν_ϵ_t)
    # prepare data matrix, arbitrarily, bids first
    P = fill(P_last, num_quotes)
    S_ref = fill(S_ref_last, num_quotes)
    A = hcat(P, S_ref, bid_ϵ_vals_t)
    A = vcat(A, hcat(P, S_ref, ask_ϵ_vals_t))
    # compute incoming net flow `ν_ϵ`
    ν_ϵ = vcat(bid_ν_ϵ_t, ask_ν_ϵ_t)
    # compute normalized spread PnL `s_ϵ` -> ν_ϵ*S_ref*(1 + ϵ)) / S_ref
    s_ϵ = [((ν_ϵ[i]*round(A[:, 2][i]*(1 + A[:, 3][i]), digits=2)) / (A[:, 2][i])) for i in 1:size(A, 1)]
    return ν_ϵ, s_ϵ, A
end

# #----- ML Utility functions -----#

function compute_mse(y_true, x, A; poly_A = true)

    if poly_A == true
        # compute least squares solution
        y_pred = A * x
        # compute mean squared error
        loss = sum((y_true .- y_pred).^2) / length(y_true)
    else
        # compute least squares solution
        y_pred = (@view A[:, 1:4]) * x
        # compute mean squared error
        loss = sum((y_true .- y_pred).^2) / length(y_true)
    end

    return loss
end

# ======================================================================================== #

"""
    AdaptiveMM_run(...)

Simulate adaptive market-making agent activity.

# Arguments
- ...

# Keywords
- 

# Returns
- 

# References
- 
"""
function AdaptiveMM_run(ticker, market_open, market_close, parameters, init_conditions, server_info; collect_data = false)
    # unpack parameters
    η_ms,γ,δ_tol,inventory_limit,unit_trade_size,trade_freq = parameters
    init_cash, init_z, num_init_quotes, num_init_rounds = init_conditions
    host_ip_address, port, username, password = server_info
    id = ticker # LOB assigned to Market Maker

    # connect to brokerage
    url = "http://$(host_ip_address):$(port)"
    Client.SERVER[] = url
    Client.createUser(username, password)
    user = Client.loginUser(username, password)

    # preallocate data structures and variables
    ν_ϵ_losses = Float64[]
    s_ϵ_losses = Float64[]
    cash_data = Float64[]
    inventory_data = Float64[]
    # bid_quote_data = Float64[]
    # ask_quote_data = Float64[]
    # S_bid_data = Float64[]
    # S_ask_data = Float64[]
    # mid_price_data = Float64[]
    # time_trade_data = DateTime[]
    new_bid = [1.0 0.0 0.0 0.0 0.0 0.0]
    new_ask = [1.0 0.0 0.0 0.0 0.0 0.0]

    # instantiate dynamic variables
    initiated = false
    σ_new = 0
    sum_returns = 0
    P_last = 0
    x_QR_ν = zeros(4) # least squares estimator, dim: (4,)
    V_market = 0
    x_QR_s = zeros(6) # least squares estimator, dim: (6,)
    sum_s = 0
    k = 0
    sum_ν = 0
    var_s = 0
    var_ν = 0
    z = init_z
    cash = init_cash
    ν_ϵ = Float64[]
    s_ϵ = Float64[]
    A = Float64[]
    𝐏_old_ν = Float64[] # 4x4 matrix
    𝐏_old_s = Float64[] # 6x6 matrix

    # hold off trading until the market opens
    if Dates.now() < market_open
        @info "(Adaptive MM) Waiting until market open..."
        pre_market_time = Dates.value(market_open - now()) / 1000 # convert to secs
        sleep(pre_market_time)
    end

    # execute trades until the market closes
    @info "(Adaptive MM) Initiating trade sequence now."
    while Dates.now() < market_close
        if initiated != true
            #----- Initialization Step -----#
            early_stoppage = false

            # preallocate storage for empirical variables
            A = zeros(Float64, (2*num_init_quotes * num_init_rounds), 3)
            ν_ϵ = zeros(2*num_init_quotes * num_init_rounds)
            s_ϵ = zeros(2*num_init_quotes * num_init_rounds)

            for cycle in 1:num_init_rounds
                # preallocate init quote vectors
                bid_order_ids_t = zeros(Int, num_init_quotes)
                bid_ϵ_vals_t = zeros(Float64, num_init_quotes)
                bid_ν_ϵ_t = fill(unit_trade_size, num_init_quotes)
                ask_order_ids_t = zeros(Int, num_init_quotes)
                ask_ϵ_vals_t = zeros(Float64, num_init_quotes)
                ask_ν_ϵ_t = fill(unit_trade_size, num_init_quotes)
                
                # post init quotes
                trade_volume_last = Client.getTradeVolume(ticker)
                P_last, S_ref_last, bid_order_ids_t, bid_ϵ_vals_t, ask_order_ids_t, ask_ϵ_vals_t = post_rand_quotes(ticker, num_init_quotes, unit_trade_size, id, 
                                        bid_order_ids_t, bid_ϵ_vals_t, ask_order_ids_t, ask_ϵ_vals_t)

                # wait 'trade_freq' seconds (at least), and longer if no quotes filled
                sleep(trade_freq)
                while length(Client.getActiveSellOrders(id, ticker)) == num_init_quotes && length(Client.getActiveBuyOrders(id, ticker)) == num_init_quotes
                    sleep(trade_freq)
                    if Dates.now() > market_close
                        early_stoppage = true
                        break
                    end
                end
                trade_volume_t = Client.getTradeVolume(ticker)

                # retrieve data for unfilled orders
                active_sell_orders = Client.getActiveSellOrders(id, ticker)
                for i in eachindex(active_sell_orders)
                    # retrieve order
                    unfilled_sell = (active_sell_orders[i])[2]
                    # cancel unfilled order
                    cancel_order = Client.cancelQuote(ticker,unfilled_sell.orderid,"SELL_ORDER",unfilled_sell.price,id)
                    early_stoppage == true ? break : nothing
                    # store data
                    idx = findfirst(x -> x==unfilled_sell.orderid, ask_order_ids_t)
                    ask_ν_ϵ_t[idx] = unit_trade_size - unfilled_sell.size
                end

                active_buy_orders = Client.getActiveBuyOrders(id, ticker)
                for i in eachindex(active_buy_orders)
                    # retrieve order
                    unfilled_buy = (active_buy_orders[i])[2]
                    # cancel unfilled order
                    cancel_order = Client.cancelQuote(ticker,unfilled_buy.orderid,"BUY_ORDER",unfilled_buy.price,id)
                    early_stoppage == true ? break : nothing
                    # store data
                    idx = findfirst(x -> x==unfilled_buy.orderid, bid_order_ids_t)
                    bid_ν_ϵ_t[idx] = unit_trade_size - unfilled_buy.size
                end

                # adjust cash and inventory
                cash, z = update_init_cash_inventory(cash, z, P_last, S_ref_last, bid_ν_ϵ_t,
                                            bid_ϵ_vals_t, ask_ν_ϵ_t, ask_ϵ_vals_t)

                # compute and store cash and inventory data
                if collect_data == true
                    push!(cash_data, cash)
                    push!(inventory_data, z)
                end

                # construct Empirical Response Table
                early_stoppage == true ? break : nothing
                ν_ϵ_t, s_ϵ_t, A_t = construct_ERTable(P_last, S_ref_last, num_init_quotes, bid_ϵ_vals_t,
                                                    bid_ν_ϵ_t, ask_ϵ_vals_t, ask_ν_ϵ_t)

                # update variables
                println("A_t = ", A_t)
                println("ν_ϵ_t = ", ν_ϵ_t)
                A[((1+2*num_init_quotes*(cycle-1)):(2*num_init_quotes*cycle)),:] = A_t
                ν_ϵ[((1+2*num_init_quotes*(cycle-1)):(2*num_init_quotes*cycle))] = ν_ϵ_t
                s_ϵ[((1+2*num_init_quotes*(cycle-1)):(2*num_init_quotes*cycle))] = s_ϵ_t
            end

            # add col of ones to design matrix (for intercept term)
            A = [ones(2*num_init_quotes * num_init_rounds) A]

            # add polynomial terms to design matrix (for curved s_ϵ relationship)
            A = [A (A[:, 4]).^2 (A[:, 4]).^3]   

            # compute initial least squares estimators
            x_QR_ν = (@view A[:, 1:4]) \ ν_ϵ # QR Decomposition
            x_QR_s = A \ s_ϵ # QR Decomposition
            println("x_QR_ν = ", x_QR_ν)
            println("size(x_QR_ν) = ", size(x_QR_ν))
            println("x_QR_s = ", x_QR_s)
            println("size(x_QR_s) = ", size(x_QR_s))
            println("A = ", A)
            println("ν_ϵ = ", ν_ϵ)
            println("s_ϵ = ", s_ϵ)
            𝐏_old_ν = @views inv((A[:, 1:4])' * (A[:, 1:4])) # for Recursive Least Squares step
            𝐏_old_s = inv(A' * A) # for Recursive Least Squares step

            # compute and store loss
            if collect_data == true
                ν_loss = compute_mse(ν_ϵ, x_QR_ν, A, poly_A=false)
                push!(ν_ϵ_losses, ν_loss)
                s_loss = compute_mse(s_ϵ, x_QR_s, A)
                push!(s_ϵ_losses, s_loss) 
            end

            # store values for online mean and variance estimates
            # https://www.johndcook.com/blog/standard_deviation/
            sum_ν = sum(ν_ϵ) # rolling sum count
            var_ν = 0 # var(ν_ϵ) # initial variance
            k = length(ν_ϵ) # number of samples, same as length(s_ϵ)
            sum_s = sum(s_ϵ) # rolling sum count
            var_s = 0 # var(s_ϵ) # initial variance

            # compute total market volume (for individual ticker) in last time interval
            V_market = trade_volume_t - trade_volume_last

            # retrieve historical price info for volatility calculation
            P_hist = @view A[:, 2]
            P_rounds = Float64[]
            for (index, value) in enumerate(P_hist)
                if index % num_init_rounds == 0
                    P_rounds = push!(P_rounds, value)
                end
            end

            # compute the volatility σ
            log_returns = [log(P_rounds[i+1] / P_rounds[i]) for i in 1:(num_init_rounds -1)]
            sum_returns += sum(log_returns)
            mean_return = sum(log_returns) / length(log_returns)
            return_variance = sum((log_returns .- mean_return).^2) / (length(log_returns) - 1)
            σ_new = sqrt(return_variance) # volatility

            # complete initialization step
            @info " (Adaptive MM) Initialization rounds complete. Starting RLS procedure now."
            initiated = true
        end

        # check stopping condition
        if Dates.now() > market_close
            break
        end

        # retrieve current market conditions (current mid-price and side-spread)
        P_t, S_ref_0 = get_price_details(ticker)
        S_ref_0 <= 0.02 ? continue : nothing # avoid small spread/error
        new_bid[2] = P_t
        new_ask[2] = P_t
        new_bid[3] = S_ref_0
        new_ask[3] = S_ref_0

        # update online volatility
        println("========================")
        println("")
        println("σ_old = ", σ_new)
        n = k/2 # number of trading invocations
        returns_t = log(P_t / P_last)
        sum_returns += returns_t
        mean_returns = sum_returns / n
        mean_returns_new = mean_returns + ((returns_t - mean_returns) / n) # mean
        σ_new = σ_new + ((returns_t - mean_returns) * (returns_t - mean_returns_new)) # std

        # update volatility estimate
        println("σ_new = ", σ_new)
        println("P_t = ", P_t)
        println("P_last = ", P_last)
        println("S_ref_0 = ", S_ref_0)
        σ = σ_new * sqrt(abs(P_t - P_last)) # normal volatility
        println("σ_normal = ", σ)
        println("V_market = ", V_market)

        # check variables
        println("sum_s = ", sum_s)
        println("k = ", k)
        println("sum_v = ", sum_ν)
        println("var_ν = ", var_ν)
        println("var_s = ", var_s)
        println("z = ", z)
        println("cash = ", cash)
        println("size(ν_ϵ) = ", size(ν_ϵ))
        println("size(s_ϵ) = ", size(s_ϵ))
        println("size(A) = ", size(A))

        #----- Pricing Policy -----#
        # STEP 1: Ensure that Market Maker adapts policy if it is getting little or no trade flow

        # compute the ϵ that gets us the closest to η_ms
        # initialize -
        ϵ_ms = Variable() # scalar
        t = Variable() # scalar (for absolute value)
        # setup problem (reformulate absolute value) and solve -
        prob = η_ms - (([1.0 P_t S_ref_0 ϵ_ms]*x_QR_ν)[1]) / V_market
        problem = minimize(t)
        problem.constraints += prob <= t
        problem.constraints += -prob <= t
        problem.constraints += -0.85 <= ϵ_ms
        problem.constraints += (((0.5*P_t) / S_ref_0) + 1) >= ϵ_ms
        # Solve the problem by calling solve!
        solve!(problem, ECOS.Optimizer; silent_solver = true)
        println("ϵ_ms = ", evaluate(ϵ_ms))

        # compute the ϵ that maximizes profit within δ_tol
        # initialize -
        cost1 = problem.optval
        ϵ_opt = Variable() # scalar
        t = Variable() # scalar
        prob = η_ms - (([1.0 P_t S_ref_0 ϵ_opt]*x_QR_ν)[1]) / V_market
        # setup problem and solve -
        p = maximize(ϵ_opt)
        p.constraints += prob <= t
        p.constraints += -prob <= t
        p.constraints += t - cost1 <= δ_tol
        p.constraints += -(t - cost1) <= δ_tol
        p.constraints += -0.85 <= ϵ_opt
        p.constraints += (((0.5*P_t) / S_ref_0) + 1) >= ϵ_opt
        solve!(p, ECOS.Optimizer; silent_solver = true)

        # Set buy and sell ϵ values
        ϵ_buy = round(p.optval, digits = 2)
        ϵ_sell = round(p.optval, digits = 2)
        println("ϵ_opt = ", ϵ_buy)
        
        # STEP 2: Skew one side (buy/sell) to attract a flow that offsets current inventory
        # initialize -
        cost2 = JuMP.Model(Ipopt.Optimizer)
        set_silent(cost2)
        ϵ_skew = 0 # scalar
        @variable(cost2, -0.85 ≤ ϵ_skew ≤ ((0.5*P_t) / S_ref_0) + 1) # mid-price ≤ ϵ_skew ≤ 50% * P_(bid/ask)_0 of way into book
        # setup problem -
        # E_s_ϵ = ([1.0 P_t S_ref_0 ϵ_skew]*x_QR_s)[1] # expected value
        # mean_s = sum_s / k
        # mean_s_ϵ = mean_s + ((E_s_ϵ - mean_s) / k)
        # var_s_ϵ = (var_s + ((E_s_ϵ - mean_s) * (E_s_ϵ - mean_s_ϵ))) / (k - 1) # variance
        # for expected value of `s_ϵ`
        @NLexpression(cost2, quad_ϵ, (ϵ_skew)^2)
        @NLexpression(cost2, cubic_ϵ, quad_ϵ * ϵ_skew)
        @NLexpression(cost2, E_s_ϵ, (1.0*x_QR_s[1]) + (P_t*x_QR_s[2]) + (S_ref_0*x_QR_s[3]) + 
                    (ϵ_skew * x_QR_s[4]) + (quad_ϵ * x_QR_s[5]) + (cubic_ϵ * x_QR_s[6]))
        @NLexpressions(
            cost2,
            begin
                mean_s, sum_s / k
                mean_s_ϵ, mean_s + ((E_s_ϵ - mean_s) / k)
                var_s_ϵ, (var_s + ((E_s_ϵ - mean_s) * (E_s_ϵ - mean_s_ϵ))) / (k - 1) # variance
            end
        )
        # for expected value of `ν_ϵ`
        E_z_ν_ϵ = z + ([1.0 P_t S_ref_0 ϵ_skew]*x_QR_ν)[1] # expected value
        mean_ν = sum_ν / k
        mean_z_ν_ϵ = mean_ν + ((E_z_ν_ϵ - mean_ν) / k)
        var_z_ν_ϵ = (var_ν + ((E_z_ν_ϵ - mean_ν) * (E_z_ν_ϵ - mean_z_ν_ϵ))) / (k - 1) # variance
        # solve the problem -
        @NLobjective(cost2, Min, -(S_ref_0 * E_s_ϵ) + γ * sqrt((S_ref_0^2 * var_s_ϵ) + (σ^2 * var_z_ν_ϵ)))
        optimize!(cost2)

        # execute actions (submit quotes)
        trade_volume_last = Client.getTradeVolume(ticker)
        ϵ_skew = round(value.(ϵ_skew), digits = 2)
        if z > 0
            # positive inventory -> skew sell-side order
            ϵ_buy = ϵ_buy
            ϵ_skew <= ϵ_sell ? ϵ_sell = ϵ_skew : ϵ_sell = ϵ_sell
            new_bid[4] = ϵ_buy; new_bid[5] = (ϵ_buy)^2; new_bid[6] = (ϵ_buy)^3
            new_ask[4] = ϵ_sell; new_ask[5] = (ϵ_sell)^2; new_ask[6] = (ϵ_sell)^3
            println("ϵ_buy = $(ϵ_buy), ϵ_sell = $(ϵ_sell)")
            P_bid = P_t - round(S_ref_0*(1 + ϵ_buy), digits=2)
            P_ask = P_t + round(S_ref_0*(1 + ϵ_sell), digits=2)
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
            # set ϵ param for hedge step
            ϵ_hedge = ϵ_sell
        elseif z < 0
            # negative inventory -> skew buy-side order
            ϵ_skew <= ϵ_buy ? ϵ_buy = ϵ_skew : ϵ_buy = ϵ_buy
            ϵ_sell = ϵ_sell
            new_bid[4] = ϵ_buy; new_bid[5] = (ϵ_buy)^2; new_bid[6] = (ϵ_buy)^3
            new_ask[4] = ϵ_sell; new_ask[5] = (ϵ_sell)^2; new_ask[6] = (ϵ_sell)^3
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
            # set ϵ param for hedge step
            ϵ_hedge = ϵ_buy
        else
            # no inventory -> no skew
            ϵ_buy = ϵ_buy
            ϵ_sell = ϵ_sell
            new_bid[4] = ϵ_buy; new_bid[5] = (ϵ_buy)^2; new_bid[6] = (ϵ_buy)^3
            new_ask[4] = ϵ_sell; new_ask[5] = (ϵ_sell)^2; new_ask[6] = (ϵ_sell)^3
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
            # set ϵ param for hedge step
            ϵ_hedge = ϵ_buy
        end

        #----- Hedging Policy -----#
        # Determine the fraction of current inventory to hedge (by initiating offsetting trade)

        # initialize -
        cost_hedge = JuMP.Model(Ipopt.Optimizer)
        set_silent(cost_hedge)
        x_frac = 0 # scalar
        Z = z # scalar
        @variable(cost_hedge, 0 <= x_frac <= 1)
        @variable(cost_hedge, -inventory_limit <= Z <= inventory_limit)
        # setup problem -
        Z = z*(1 - x_frac)
        E_zx_ν_ϵ = Z + ([1.0 P_t S_ref_0 ϵ_hedge]*x_QR_ν)[1] # expected value
        mean_ν = sum_ν / k
        mean_zx_ν_ϵ = mean_ν + ((E_zx_ν_ϵ - mean_ν) / k)
        var_zx_ν_ϵ = (var_ν + ((E_zx_ν_ϵ - mean_ν) * (E_zx_ν_ϵ - mean_zx_ν_ϵ))) / (k - 1) # variance
        # solve the problem -
        @NLobjective(cost_hedge, Min, (abs(x_frac*z) * S_ref_0) + γ * sqrt(σ^2 * var_zx_ν_ϵ))
        optimize!(cost_hedge)

        # execute actions (submit hedge trades)
        x_frac = round(value.(x_frac), digits = 2)
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

        # wait 'trade_freq' seconds (at least), and longer if no trades occur
        sleep(trade_freq)
        while Client.getTradeVolume(ticker) == trade_volume_last
            sleep(trade_freq)
            if Dates.now() > market_close
                @info "(Adaptive MM) Market closed. Exiting early."
                early_stoppage = true
                break
            end
        end
        trade_volume_t = Client.getTradeVolume(ticker)

        # reset data structures
        # ν_new_bid[1] = unit_trade_size
        # ν_new_ask[1] = unit_trade_size
        ν_new_bid = [unit_trade_size]
        ν_new_ask = [unit_trade_size]
        ν_new = 0
        s_new = 0
        A_new = 0

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
                                        new_bid[4], ν_new_ask, new_ask[4])

        # compute and store cash and inventory data
        if collect_data == true
            push!(cash_data, cash)
            push!(inventory_data, z)
        end

        # Update Estimators: Recursive Least Squares w/ multiple observations
        # new observation k
        ν_new = vcat(ν_ϵ, vcat(ν_new_bid, ν_new_ask))
        A_new = vcat(A, vcat(new_bid, new_ask))
        s_new = [((ν_new[i]*A_new[:, 3][i]*(1 + A_new[:, 4][i])) / (A_new[:, 3][i])) for i in 1:size(A_new, 1)]
        # update 𝐏_k
        𝐏_new_ν = @views 𝐏_old_ν - 𝐏_old_ν*(A_new[:, 1:4])'*inv(I + (A_new[:, 1:4])*𝐏_old_ν*(A_new[:, 1:4])')*(A_new[:, 1:4])*𝐏_old_ν
        𝐏_new_s = 𝐏_old_s - 𝐏_old_s*A_new'*inv(I + A_new*𝐏_old_s*A_new')*A_new*𝐏_old_s
        # compute 𝐊_k
        𝐊_k_ν = 𝐏_new_ν*(@view A_new[:, 1:4])'
        𝐊_k_s = 𝐏_new_s*A_new'
        # compute new estimator
        x_QR_ν = x_QR_ν + 𝐊_k_ν*(ν_new .- (@view A_new[:, 1:4])*x_QR_ν)
        x_QR_s = x_QR_s + 𝐊_k_s*(s_new .- A_new*x_QR_s)

        # update Empirical Response Table and related variables for next time step
        V_market = trade_volume_t - trade_volume_last
        ν_ϵ = ν_new
        s_ϵ = s_new
        A = A_new
        𝐏_old_ν = 𝐏_new_ν
        𝐏_old_s = 𝐏_new_s

        # compute and store loss
        if collect_data == true
            ν_loss = compute_mse(ν_ϵ, x_QR_ν, A, poly_A=false)
            push!(ν_ϵ_losses, ν_loss)
            s_loss = compute_mse(s_ϵ, x_QR_s, A)
            push!(s_ϵ_losses, s_loss) 
        end

        # update online variance and values for future online estimates
        # https://www.johndcook.com/blog/standard_deviation/
        for i in eachindex(ν_new[k+1:end])
            mean_ν = sum_ν / (k + i - 1) # using prev sum & k
            mean_ν_new = mean_ν + ((ν_new[k+i] - mean_ν) / (k + i))
            var_ν = (var_ν + ((ν_new[k+i] - mean_ν) * (ν_new[k+i] - mean_ν_new))) / (k + i) # new variance
        end
        # repeat for s
        for i in eachindex(s_new[k+1:end])
            mean_s = sum_s / (k + i - 1) # using prev sum & k
            mean_s_new = mean_s + ((s_new[k+i] - mean_s) / (k + i))
            var_s = (var_s + ((s_new[k+i] - mean_s) * (s_new[k+i] - mean_s_new))) / (k + i) # new variance
        end

        # update values
        sum_ν += sum(ν_new[k+1:end]) # rolling sum count
        sum_s += sum(s_new[k+1:end]) # rolling sum count
        k = length(ν_ϵ) # number of samples, same as length(s_ϵ)
        P_last = P_t # for volatility update step
    end
    @info "(Adaptive MM) Trade sequence complete."

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
        # for ML loss - prepare tabular dataset
        loss_data = DataFrame(ν_ϵ_loss = ν_ϵ_losses, s_ϵ_loss = s_ϵ_losses)
        # for ML loss - create save path
        loss_savepath = mkpath("../../Data/ABMs/Exchange/ML_loss")
        # for ML loss - save data
        CSV.write("$(loss_savepath)/RLS_losses_AMM_id$(id).csv", loss_data)

        # for cash and inventory - prepare tabular dataset
        cash_inv_data = DataFrame(cash_dt = cash_data, inv_dt = inventory_data)
        # for cash and inventory - create save path
        cash_inv_savepath = mkpath("../../Data/ABMs/Exchange/cash_inv")
        # for cash and inventory - save data
        CSV.write("$(cash_inv_savepath)/cash_inv_data_AMM_id$(id).csv", cash_inv_data)

        # for model data - prepare tabular dataset
        model_data = DataFrame(mid_price_dt = A[:, 2], mid_spread_dt = A[:, 3], ϵ_dt = A[:, 4], ν_ϵ_dt = ν_ϵ, s_ϵ_dt = s_ϵ)
        # for model data - create save path
        model_data_savepath = mkpath("../../Data/ABMs/Exchange/model_data")
        # for model data - save data
        CSV.write("$(model_data_savepath)/model_data_AMM_id$(id).csv", model_data)

        # for model parameters - save data
        open("$(model_data_savepath)/model_params_AMM_id$(id).txt", "w") do file
            write(file, " Agent Parameters \n")
            write(file, "----------------- \n")
            write(file, "η_ms = $η_ms \n")
            write(file, "γ = $γ \n")
            write(file, "δ_tol = $δ_tol \n")
            write(file, "inventory_limit = $inventory_limit \n")
            write(file, "unit_trade_size = $unit_trade_size \n")
            write(file, "trade_freq = $trade_freq \n")
            write(file, "\n Initial Conditions \n")
            write(file, "----------------- \n")
            write(file, "cash = $init_cash \n")
            write(file, "inventory = $init_z \n")
            write(file, "num_init_quotes = $num_init_quotes \n")
            write(file, "num_init_rounds = $num_init_rounds \n")
            write(file, "\n Estimators \n")
            write(file, "----------------- \n")
            write(file, "x_QR_ν = [")
            for i in eachindex(x_QR_ν)
                write(file, "$(x_QR_ν[i]), ")
            end
            write(file, "] \n")
            write(file, "x_QR_s = [")
            for i in eachindex(x_QR_s)
                write(file, "$(x_QR_s[i]), ")
            end
            write(file, "] \n")
        end
    end
end