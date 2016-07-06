--- Interface for cursors.
-- @module rethinkdb.cursor
-- @author Adam Grandquist
-- @license Apache
-- @copyright Adam Grandquist 2016

local convert_pseudotype = require'rethinkdb.internal.convert_pseudotype'
local errors = require'rethinkdb.errors'
local protodef = require'rethinkdb.internal.protodef'

local unpack = _G.unpack or table.unpack

local Response = protodef.Response

local COMPILE_ERROR = Response.COMPILE_ERROR
local SUCCESS_ATOM = Response.SUCCESS_ATOM
local SUCCESS_PARTIAL = Response.SUCCESS_PARTIAL
local SUCCESS_SEQUENCE = Response.SUCCESS_SEQUENCE
local CLIENT_ERROR = Response.CLIENT_ERROR
local RUNTIME_ERROR = Response.RUNTIME_ERROR
local WAIT_COMPLETE = Response.WAIT_COMPLETE

local function cursor(token, del_query, opts, process_response, protocol_inst, root)
  local responses = {}
  local _callback, end_flag, _type

  local meta_table = {}

  function meta_table.__tostring()
    return "RethinkDB Cursor"
  end

  local cursor_inst = setmetatable({r = protocol_inst.r}, meta_table)

  local function get_response(reqest_token)
    -- Buffer data, execute return results if need be
    local next_token, response, err
    while true do
      next_token, response = protocol_inst.query_response()
      if not next_token then
        return nil, response
      end
      protocol_inst.continue_query(next_token)
      response, err = cursor_inst.r.decode(response)
      if err and not response then
        return nil, err
      end
      if next_token == reqest_token then return response end
      process_response(response, next_token)
    end
  end

  local function run_cb(callback)
    local response = responses[1]
    if not response then return callback() end
    -- Behavior varies considerably based on response type
    -- Error responses are not discarded, and the error will be sent to all future callbacks
    local t = response.t
    if t == SUCCESS_ATOM or t == SUCCESS_PARTIAL or t == SUCCESS_SEQUENCE then
      local row, err = convert_pseudotype(cursor_inst.r, response.r[1], opts)

      if err then
        row = response.r[1]
      end

      table.remove(response.r, 1)
      if not next(response.r) then table.remove(responses, 1) end

      return callback(err, row)
    end
    _callback = nil
    if t == COMPILE_ERROR then
      return callback(errors.ReQLCompileError(response.r[1], root, response.b))
    elseif t == CLIENT_ERROR then
      return callback(errors.ReQLClientError(response.r[1], root, response.b))
    elseif t == RUNTIME_ERROR then
      return callback(errors.ReQLRuntimeError(response.r[1], root, response.b))
    elseif t == WAIT_COMPLETE then
      return callback()
    end
    return callback(errors.ReQLDriverError('Unknown response type ' .. t))
  end

  local function add_response(response)
    local t = response.t
    if not _type then
      if response.n then
        _type = response.n
      else
        _type = 'finite'
      end
    end
    if response.r[1] or t == WAIT_COMPLETE then
      table.insert(responses, response)
    end
    if t ~= SUCCESS_PARTIAL then
      -- We got the final document for this cursor
      end_flag = true
      del_query(token)
    end
    while _callback and responses[1] do
      run_cb(_callback)
    end
  end

  function cursor_inst.set(callback)
    _callback = callback
  end

  function cursor_inst.close(callback)
    if not end_flag then
      end_flag = true
      if protocol_inst then
        protocol_inst.end_query(token)
        del_query(token)
      end
    end
    if callback then return callback() end
  end

  function cursor_inst.each(callback, on_finished)
    local e
    local function cb(err, data)
      if err then
        e = err
        return
      end
      return callback(data)
    end
    cursor_inst.set(cb)
    while not end_flag do
      local response, err = get_response(token)
      if err and not response then
        cb(errors.ReQLDriverError(err))
        break
      end
      add_response(response)
    end
    if on_finished then
      return on_finished(e)
    end
  end

  function cursor_inst.next(callback)
    local old_callback = _callback
    local res = nil
    local function on_data(data)
      cursor_inst.set(old_callback)
      res = {callback(nil, data)}
    end
    local function on_err(err)
      cursor_inst.set(old_callback)
      if res and not err then return unpack(res) end
      return callback(err)
    end
    return cursor_inst.each(on_data, on_err)
  end

  function cursor_inst.to_array(callback)
    local arr = {}

    local function cb(row)
      table.insert(arr, row)
    end

    local function on_finished(err)
      return callback(err, arr)
    end

    return cursor_inst.each(cb, on_finished)
  end

  return cursor_inst, add_response
end

return cursor
