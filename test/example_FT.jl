using TradingAgents, Dates

## Example use case
parameters = (
    # init_cash_range = 10000.0:0.01:30000.0,
    # init_shares_range = 0:1:120,
    init_cash_range = 5000.0:0.01:15000.0,
    init_shares_range = 0:1:60,
    prob_wait = 0.5, # probability of halting (per active trader)
    trade_freq = 5, # how many seconds to wait (if `prob_wait` invoked)
    num_ids = 30 + 20 # number of reserved ids set aside for other agents
)

server_info = (
    host_ip_address = "0.0.0.0",
    port = "8080",
    username = "Fundamental Trader",
    password = "value123"
)

num_traders, num_assets = 10, 1
market_open = Dates.now() + Dates.Second(8)
market_close = market_open + Dates.Minute(5)

FT_run(num_traders, num_assets, market_open, market_close, parameters, server_info)

# include("test/example_FT.jl")