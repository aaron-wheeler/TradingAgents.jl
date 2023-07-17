using TradingAgents, Dates

## Example use case
parameters = (
    ϵ_min = -0.5, # lower bound for price deviation variable
    ϵ_max = 0.5, # upper bound for price deviation variable
    inventory_limit = 3000, # maximum and minimum number of share holdings allowed
    unit_trade_size = 15, # amount of shares behind each quote
    trade_freq = 10 # 20 # avg seconds between trades; based on Paddrik et al. (2012) and Paulin et al. (2019)
)

server_info = (
    host_ip_address = "0.0.0.0",
    port = "8080",
    username = "Parallel Market Maker",
    password = "liquidity000"
)

num_agents, num_assets = 10, 1 # 320, 1 # based on Paddrik et al. (2012) and Paulin et al. (2019)

PMM_run(num_agents, num_assets, parameters, server_info, print_msg = true)

# include("test/example_PMM.jl")