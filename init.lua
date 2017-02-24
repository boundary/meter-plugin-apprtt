--@vitiwari
-- plugin to track App Round Trip Time using lua
local framework = require('framework')
local net = require('net')
local json = require('json')
local clone = framework.table.clone
local Plugin = framework.Plugin
local DataSource = framework.DataSource
local DataSourcePoller = framework.DataSourcePoller
local PollerCollection = framework.PollerCollection
local ipack = framework.util.ipack
local parseJson = framework.util.parseJson
local notEmpty = framework.string.notEmpty

--Getting the parameters from params.json.
local params = framework.params
local hostName =nil
local pollers = nil
local plugin = nil


-- vitiwari
-- This datasource is to get Average TCP Round Trip Time
 local AppRTTDataSource = DataSource:extend()

-- AppRTTDataSource
-- @name ProcessCpuDataSource:new
-- @param params a table with the configuraiton parameters.
function AppRTTDataSource:initialize(params)
  local options = params or {}
  self.options = options
  self.items = {}
  self.count = 0
  local ck = function()
  end
  local socket1 = net.createConnection(8140, '127.0.0.1', ck)
  local subsMsg="{\"subscriber\" : \""..options.source.."\", \"flow\":{\"filter\":{\"options\":{\"include_loopback\":true}, \"filters\":[\"tcp\"]}}}"
  socket1:write(subsMsg)
  socket1:on('data',function(data)
      local success, parsed = parseJson(data)
      if not success then
       self:emit('error', '[Not valid JSON] The subscription flow response can not be parsed. Please report  ')
      end

      if parsed.error then
       self:emit('error', parsed.error..", Please delete the plugin and install again with correct parameters.")
       socket1:destroy()
      elseif parsed.flows then
        for k, v in pairs(parsed.flows) do
          if v.aRtt ~= 0 then
            AppRTTDataSource:add(v.aRtt)
          end
        end
      else
        self:emit('error', "Plugin is not working as the subscription flow response syntax has changed, Please report ")
       socket1:destroy()
      end
  end)


  socket1:on('error', function (err)
    self:emit('error', 'There is an issue with socket connection to meter : '.. err.message)
    socket1:destroy()
  end)
end


function AppRTTDataSource:add( value)
      self.count = self.count + 1
      self.items[self.count] = value
 end

 function AppRTTDataSource:averageTillNow()
      local llist=clone(self.items);
      self.items = {}
      self.count = 0
      local sum = 0
      local count = 0
      if llist then
       for k, v in pairs(llist) do
        sum=sum + v
        count=count + 1
       end
      end
      local avg = 0
      if count > 0 then
       avg= sum/count
      end
      return avg
 end

--AppRTTDataSource fetch function
function AppRTTDataSource:fetch(context, callback,params)
  local options = clone(self.options)
  local avg = AppRTTDataSource:averageTillNow()
  local result ={}  
  table.insert(result, {metric = "TCP_RTT", value = avg , source = options.source }) 
  callback(result)
end




-- Create an options object containing required parameters and values
local function createOptions(item)
   local options = {}
   options.source = notEmpty(item.source,hostName)
   options.filter = item.filter
   options.pollInterval = notEmpty(tonumber(item.pollInterval),5000)
   return options
end

-- Create data source 
local function createDataSource(item)
    local options = createOptions(item)
    return AppRTTDataSource:new(options)
end

-- Create Poller
local function createPoller(params)
    local cs = createDataSource(params)
    local poller= DataSourcePoller:new(notEmpty(tonumber(params.pollInterval),5000), cs)
    return poller;
end

-- Create a socket connection to make JSON RPC call for getting system information
-- This will get called on intallation of plugin
local socket = net.createConnection(9192, '127.0.0.1', nil)
socket:write('{"jsonrpc":"2.0","id":3,"method":"get_system_info","params":{}}')

-- once using JSON RPC we get the hostname 
-- Set the hostname to options, create pollers, datasource and run the plugin  
socket:once('data',function(data)
  local sucess,  parsed = parseJson(data)
  hostName =  parsed.result.hostname--:gsub("%-", "")
  socket:destroy()
  pollers = createPoller(params)
  plugin = Plugin:new(params, pollers)
    
  function plugin:onParseValues(data, extra)

    local measurements = {}
    local measurement = function (...)
      ipack(measurements, ...)
    end
    for K,V  in pairs(data) do
      measurement(V.metric, V.value, nil, V.source)
    end

    return measurements
  end
  plugin:run()
end)

