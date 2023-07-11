using TradingAgents, Dates

## Example use case
parameters = (
    id = 5, # market maker identifier, must be less than Brokerage.Mapper.MM_COUNTER
    ϵ_min = -0.5, # lower bound for price deviation variable
    ϵ_max = 0.5, # upper bound for price deviation variable
    inventory_limit = 3000, # maximum and minimum number of share holdings allowed
    unit_trade_size = 15, # amount of shares behind each quote
    trade_freq = 2 # seconds between each trading invocation
)

init_conditions = (
    cash = 0, # initial cash balance
    z = 0, # initial inventory
)

server_info = (
    host_ip_address = "0.0.0.0",
    port = "8080",
    username = "Random Market Maker",
    password = "liquidity000"
)

ticker = 1

RandomMM_run(ticker, parameters, init_conditions, server_info, collect_data = true)

# include("test/example_RandomMM.jl")