-- @vitiwari
-- plugin to track App Round Trip Time using lua
local framework = require('framework')
local net = require('net')
local json = require('json')

local Plugin = framework.Plugin
local AppRTTDataSource = framework.AppRTTDataSource
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

-- Removed call back function to be passed in net.createConnection 
-- passing nil in place of callBack as of now
-- local ck = function()
-- end
-- local socket = net.createConnection(9192, '127.0.0.1', ck)
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

