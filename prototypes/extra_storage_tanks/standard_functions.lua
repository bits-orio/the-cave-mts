local standard_functions = {}

function standard_functions.round_number(num, decimals)
  decimals = 10 ^ (decimals or 0)
  num = num * decimals
  if num >= 0 then num = math.floor(num + 0.5) else num = math.ceil(num - 0.5) end
  return num / decimals
end

return standard_functions
