local json = require('json')
local mime = require('mime')
local socket = require('socket')

-- r is both the main export object for the module
-- and a function that shortcuts `r.expr`.
local r = {}
setmetatable(r, {
  __call = function(cls, ...)
    return r.expr(...)
  end
})

local Connection, Cursor
local DatumTerm, ReQLOp, MakeArray, MakeObj, Var, PolygonSub
local JavaScript, Http, Json, Binary, Args, Error, Random, Db
local Table, Get, GetAll, Eq, Ne, Lt, Le, Gt, Ge, Not, Add, Sub, Mul, Div, Mod
local Append, Prepend, Difference, SetInsert, SetUnion, SetIntersection
local SetDifference, Slice, Skip, Limit, GetField, Bracket, Contains, InsertAt
local SpliceAt, DeleteAt, ChangeAt, HasFields, WithFields, Keys, Changes
local Object, Pluck, IndexesOf, Without, Merge, Between, Reduce, Map, Filter
local ConcatMap, OrderBy, Distinct, Count, Union, Nth, Match, Split, Upcase
local Downcase, IsEmpty, Group, Sum, Avg, Min, Max, InnerJoin, OuterJoin
local EqJoin, Zip, CoerceTo, Ungroup, TypeOf, Info, Sample, Update, Delete
local Replace, Insert, DbCreate, DbDrop, DbList, TableCreate, TableDrop
local TableList, IndexCreate, IndexDrop, IndexRename, IndexList, IndexStatus
local IndexWait, Sync, FunCall, Default, Branch, Any, All, ForEach, Func, Asc
local Desc, Literal, ISO8601, ToISO8601, EpochTime, ToEpochTime, Now
local InTimezone, During, Date, TimeOfDay, Timezone, Year, Month, Day
local DayOfWeek, DayOfYear, Hours, Minutes, Seconds, Time, GeoJson, ToGeoJson
local Point, Line, Polygon, Distance, Intersects, Includes, Circle
local GetIntersecting, GetNearest, Fill, UUID, Monday, Tuesday, Wednesday
local Thursday, Friday, Saturday, Sunday, January, February, March, April, May
local June, July, August, September, October, November, December, ToJsonString
local ReQLDriverError, ReQLServerError, ReQLRuntimeError, ReQLCompileError
local ReQLClientError, ReQLQueryPrinter, ReQLError

function class(name, parent, base)
  local index, init

  if base == nil then
    base = parent
    parent = nil
  end

  if type(base) == 'function' then
    base = {__init = base}
  end

  if parent and parent.__base then
    setmetatable(base, parent.__base)
  else
    index = base
  end

  init = base.__init
  base.__init = nil
  base.__index = base

  local _class_0 = setmetatable({
    __name = name,
    __init = init,
    __base = base,
    __parent = parent
  }, {
    __index = index or function(cls, name)
      local val = rawget(base, name)
      if val == nil then
        return parent[name]
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local self = setmetatable({}, cls.__base)
      cls.__init(self, ...)
      return self
    end
  })
  base.__class = _class_0

  if parent and parent.__inherited then
    parent.__inherited(parent, _class_0)
  end

  return _class_0
end

function is_instance(class, obj)
  if type(obj) ~= 'table' then return false end

  local obj_cls = obj.__class
  while obj_cls do
    if obj_cls.__name == class.__name then
      return true
    end
    obj_cls = obj_cls.__parent
  end

  return false
end

function intsp(seq)
  if seq[1] == nil then
    return {}
  end
  local res = {seq[1]}
  for i=2, #seq do
    table.insert(res, ', ')
    table.insert(res, seq[i])
  end
  return res
end

function kved(optargs)
  return {
    '{',
    intsp((function()
      local _accum_0 = {}
      local i = 1
      for k, v in pairs(optargs) do
        _accum_0[i] = {k, ': ', v}
        i = i + 1
      end
      return _accum_0
    end)()),
    '}'
  }
end

function intspallargs(args, optargs)
  local argrepr = {}
  if #args > 0 then
    table.insert(argrepr, intsp(args))
  end
  if optargs and #optargs > 0 then
    if #argrepr > 0 then
      table.insert(argrepr, ', ')
    end
    table.insert(argrepr, kved(optargs))
  end
  return argrepr
end

function should_wrap(arg)
  return is_instance(DatumTerm, arg) or is_instance(MakeArray, arg) or is_instance(MakeObj, arg)
end

ReQLError = class(
  'ReQLError',
  function(self, msg, term, frames)
    self.msg = msg
    self.message = self.__class.__name .. ' ' .. msg
    if term then
      self.message = self.message .. ' in:\n' .. ReQLQueryPrinter(term, frames):print_query()
    end
  end
)

ReQLDriverError = class('ReQLDriverError', ReQLError, {})

ReQLServerError = class('ReQLServerError', ReQLError, {})

ReQLRuntimeError = class('ReQLRuntimeError', ReQLServerError, {})
ReQLCompileError = class('ReQLCompileError', ReQLServerError, {})
ReQLClientError = class('ReQLClientError', ReQLServerError, {})

ReQLQueryPrinter = class(
  'ReQLQueryPrinter',
  {
    __init = function(self, term, frames)
      self.term = term
      self.frames = frames
    end,
    print_query = function(self)
      local carrots
      if #self.frames == 0 then
        carrots = {self:carrotify(self:compose_term(self.term))}
      else
        carrots = self:compose_carrots(self.term, self.frames)
      end
      carrots = self:join_tree(carrots):gsub('[^%^]', '')
      return self:join_tree(self:compose_term(self.term)) .. '\n' .. carrots
    end,
    compose_term = function(self, term)
      if type(term) ~= 'table' then return '' .. term end
      local args = {}
      for i, arg in ipairs(term.args) do
        args[i] = self:compose_term(arg)
      end
      local optargs = {}
      for key, arg in pairs(term.optargs) do
        optargs[key] = self:compose_term(arg)
      end
      return term:compose(args, optargs)
    end,
    compose_carrots = function(self, term, frames)
      local frame = table.remove(frames, 1)
      local args = {}
      for i, arg in ipairs(term.args) do
        if frame == (i - 1) then
          args[i] = self:compose_carrots(arg, frames)
        else
          args[i] = self:compose_term(arg)
        end
      end
      local optargs = {}
      for key, arg in pairs(term.optargs) do
        if frame == key then
          optargs[key] = self:compose_carrots(arg, frames)
        else
          optargs[key] = self:compose_term(arg)
        end
      end
      if frame then
        return term.compose(args, optargs)
      end
      return self:carrotify(term.compose(args, optargs))
    end,
    carrot_marker = {},
    carrotify = function(self, tree)
      return {carrot_marker, tree}
    end,
    join_tree = function(self, tree)
      local str = ''
      for _, term in ipairs(tree) do
        if type(term) == 'table' then
          if #term == 2 and term[1] == self.carrot_marker then
            str = str .. self:join_tree(term[2]):gsub('.', '^')
          else
            str = str .. self:join_tree(term)
          end
        else
          str = str .. term
        end
      end
      return str
    end
  }
)

-- AST classes

ReQLOp = class(
  'ReQLOp',
  {
    __init = function(self, optargs, ...)
      optargs = optargs or {}
      self.args = {...}
      local first = self.args[1]
      if self.tt == 69 then
        local args = {}
        local arg_nums = {}
        for i=1, optargs.arity or 1 do
          table.insert(arg_nums, ReQLOp.next_var_id)
          table.insert(args, Var({}, ReQLOp.next_var_id))
          ReQLOp.next_var_id = ReQLOp.next_var_id + 1
        end
        first = first(unpack(args))
        if first == nil then
          error(ReQLDriverError('Anonymous function returned `nil`. Did you forget a `return`?'))
        end
        optargs.arity = nil
        self.args = {MakeArray({}, arg_nums), r.expr(first)}
      elseif self.tt == 155 then
        if is_instance(ReQLOp, first) then
        elseif type(first) == 'string' then
          self.base64_data = mime.b64(first)
        else
          error('Parameter to `r.binary` must be a string or ReQL query.')
        end
      elseif self.tt == 2 then
        self.args = first
      elseif self.tt == 3 then
      else
        for i, a in ipairs(self.args) do
          self.args[i] = r.expr(a)
        end
      end
      self.optargs = optargs
    end,
    build = function(self)
      if self.tt == 155 and (not self.args[1]) then
        return {
          ['$reql_type$'] = 'BINARY',
          data = self.base64_data
        }
      end
      if self.tt == 2 then
        local args = {}
        for i, arg in ipairs(self.args) do
          if is_instance(ReQLOp, arg) then
            args[i] = arg:build()
          else
            args[i] = arg
          end
        end
        return {self.tt, args}
      end
      if self.tt == 3 then
        local res = {}
        for key, val in pairs(self.optargs) do
          res[key] = val:build()
        end
        return res
      end
      local args = {}
      for i, arg in ipairs(self.args) do
        args[i] = arg:build()
      end
      res = {self.tt, args}
      if #self.optargs > 0 then
        local opts = {}
        for key, val in pairs(self.optargs) do
          opts[key] = val:build()
        end
        table.insert(res, opts)
      end
      return res
    end,
    compose = function(self, args, optargs)
      if self.tt == 2 then
        return {
          '{',
          intsp(args),
          '}'
        }
      end
      if self.tt == 3 then
        return kved(optargs)
      end
      if self.tt == 10 then
        if not args then return {} end
        for i, v in ipairs(args) do
          args[i] = 'var_' .. v
        end
        return args
      end
      if self.tt == 155 then
        if self.args[1] then
          return {
            'r.binary(',
            intspallargs(args, optargs),
            ')'
          }
        else
          return 'r.binary(<data>)'
        end
      end
      if self.tt == 13 then
        return {
          'r.row'
        }
      end
      if self.tt == 15 then
        if is_instance(Db, self.args[1]) then
          return {
            args[1],
            ':table(',
            intspallargs((function()
              local _accum_0 = {}
              for _index_0 = 2, #args do
                _accum_0[_index_0 - 1] = args[_index_0]
              end
              return _accum_0
            end)(), optargs),
            ')'
          }
        else
          return {
            'r.table(',
            intspallargs(args, optargs),
            ')'
          }
        end
      end
      if self.tt == 170 then
        return {
          args[1],
          '(',
          args[2],
          ')'
        }
      end
      if self.tt == 69 then
        if ivar_scan(self.args[2]) then
          return {
            args[2]
          }
        end
        local var_str = ''
        for i, arg in ipairs(args[1][2]) do -- ['0', ', ', '1']
          if i % 2 == 0 then
            var_str = var_str .. Var.compose(arg)
          else
            var_str = var_str .. arg
          end
        end
        return {
          'function(',
          var_str,
          ') return ',
          args[1],
          ' end'
        }
      end
      if self.tt == 64 then
        if #args > 2 then
          return {
            'r.do_(',
            intsp((function()
              local _accum_0 = {}
              for _index_0 = 2, #args do
                _accum_0[_index_0 - 1] = args[_index_0]
              end
              return _accum_0
            end)()),
            ', ',
            args[1],
            ')'
          }
        end
        if should_wrap(self.args[1]) then
          args[1] = {
            'r(',
            args[1],
            ')'
          }
        end
        return {
          args[2],
          '.do_(',
          args[1],
          ')'
        }
      end
      if should_wrap(self.args[1]) then
        args[1] = {
          'r(',
          args[1],
          ')'
        }
      end
      return {
        args[1],
        ':',
        self.st,
        '(',
        intspallargs((function()
          local _accum_0 = {}
          for _index_0 = 2, #args do
            _accum_0[_index_0 - 1] = args[_index_0]
          end
          return _accum_0
        end)(), optargs),
        ')'
      }
    end,
    run = function(self, connection, options, callback)
      -- Valid syntaxes are
      -- connection, callback
      -- connection, options, callback
      -- connection, nil, callback

      -- Handle run(connection, callback)
      if type(options) == 'function' then
        if not callback then
          callback = options
          options = {}
        else
          return options(ReQLDriverError('Second argument to `run` cannot be a function if a third argument is provided.'))
        end
      end
      -- else we suppose that we have run(connection[, options][, callback])
      options = options or {}

      if type(connection._start) ~= 'function' then
        if callback then
          return callback(ReQLDriverError('First argument to `run` must be an open connection.'))
        end
        return
      end

      return connection:_start(self, callback, options)
    end,
    next_var_id = 0,
    eq = function(...)
      return Eq({}, ...)
    end,
    ne = function(...)
      return Ne({}, ...)
    end,
    lt = function(...)
      return Lt({}, ...)
    end,
    le = function(...)
      return Le({}, ...)
    end,
    gt = function(...)
      return Gt({}, ...)
    end,
    ge = function(...)
      return Ge({}, ...)
    end,
    not_ = function(...)
      return Not({}, ...)
    end,
    add = function(...)
      return Add({}, ...)
    end,
    sub = function(...)
      return Sub({}, ...)
    end,
    mul = function(...)
      return Mul({}, ...)
    end,
    div = function(...)
      return Div({}, ...)
    end,
    mod = function(...)
      return Mod({}, ...)
    end,
    append = function(...)
      return Append({}, ...)
    end,
    prepend = function(...)
      return Prepend({}, ...)
    end,
    difference = function(...)
      return Difference({}, ...)
    end,
    set_insert = function(...)
      return SetInsert({}, ...)
    end,
    set_union = function(...)
      return SetUnion({}, ...)
    end,
    set_intersection = function(...)
      return SetIntersection({}, ...)
    end,
    set_difference = function(...)
      return SetDifference({}, ...)
    end,
    slice = function(self, left, right_or_opts, opts)
      if opts then
        return Slice(opts, self, left, right_or_opts)
      end
      if right_or_opts then
        if (type(right_or_opts) == 'table') and (not is_instance(ReQLOp, right_or_opts)) then
          return Slice(right_or_opts, self, left)
        end
        return Slice({}, self, left, right_or_opts)
      end
      return Slice({}, self, left)
    end,
    skip = function(...)
      return Skip({}, ...)
    end,
    limit = function(...)
      return Limit({}, ...)
    end,
    get_field = function(...)
      return GetField({}, ...)
    end,
    contains = function(...)
      return Contains({}, ...)
    end,
    insert_at = function(...)
      return InsertAt({}, ...)
    end,
    splice_at = function(...)
      return SpliceAt({}, ...)
    end,
    delete_at = function(...)
      return DeleteAt({}, ...)
    end,
    change_at = function(...)
      return ChangeAt({}, ...)
    end,
    indexes_of = function(...)
      return IndexesOf({}, ...)
    end,
    has_fields = function(...)
      return HasFields({}, ...)
    end,
    with_fields = function(...)
      return WithFields({}, ...)
    end,
    keys = function(...)
      return Keys({}, ...)
    end,
    changes = function(...)
      return Changes({}, ...)
    end,

    -- pluck and without on zero fields are allowed
    pluck = function(...)
      return Pluck({}, ...)
    end,
    without = function(...)
      return Without({}, ...)
    end,
    merge = function(...)
      return Merge({}, ...)
    end,
    between = function(self, left, right, opts)
      return Between(opts, self, left, right)
    end,
    reduce = function(...)
      return Reduce({arity = 2}, ...)
    end,
    map = function(...)
      return Map({}, ...)
    end,
    filter = function(self, predicate, opts)
      return Filter(opts, self, predicate)
    end,
    concat_map = function(...)
      return ConcatMap({}, ...)
    end,
    distinct = function(self, opts)
      return Distinct(opts, self)
    end,
    count = function(...)
      return Count({}, ...)
    end,
    union = function(...)
      return Union({}, ...)
    end,
    nth = function(...)
      return Nth({}, ...)
    end,
    to_json = function(...)
      return ToJsonString({}, ...)
    end,
    match = function(...)
      return Match({}, ...)
    end,
    split = function(...)
      return Split({}, ...)
    end,
    upcase = function(...)
      return Upcase({}, ...)
    end,
    downcase = function(...)
      return Downcase({}, ...)
    end,
    is_empty = function(...)
      return IsEmpty({}, ...)
    end,
    inner_join = function(...)
      return InnerJoin({}, ...)
    end,
    outer_join = function(...)
      return OuterJoin({}, ...)
    end,
    eq_join = function(self, left_attr, right, opts)
      return EqJoin(opts, self, r.expr(left_attr), right)
    end,
    zip = function(...)
      return Zip({}, ...)
    end,
    coerce_to = function(...)
      return CoerceTo({}, ...)
    end,
    ungroup = function(...)
      return Ungroup({}, ...)
    end,
    type_of = function(...)
      return TypeOf({}, ...)
    end,
    update = function(self, func, opts)
      return Update(opts, self, Func({}, func))
    end,
    delete = function(self, opts)
      return Delete(opts, self)
    end,
    replace = function(self, func, opts)
      return Replace(opts, self, Func({}, func))
    end,
    do_ = function(self, ...)
      local args = {...}
      local func = Func({arity = args.n - 1}, args[args.n])
      args[args.n] = nil
      return FunCall({}, func, self, unpack(args))
    end,
    default = function(...)
      return Default({}, ...)
    end,
    any = function(...)
      return Any({}, ...)
    end,
    all = function(...)
      return All({}, ...)
    end,
    for_each = function(...)
      return ForEach({}, ...)
    end,
    sum = function(...)
      return Sum({}, ...)
    end,
    avg = function(...)
      return Avg({}, ...)
    end,
    min = function(...)
      return Min({}, ...)
    end,
    max = function(...)
      return Max({}, ...)
    end,
    info = function(...)
      return Info({}, ...)
    end,
    sample = function(...)
      return Sample({}, ...)
    end,
    group = function(self, ...)
      -- Default if no opts dict provided
      local opts = {}
      local fields = {...}

      -- Look for opts dict
      if fields.n > 0 then
        local perhaps_opt_dict = fields[fields.n]
        if (type(perhaps_opt_dict) == 'table') and not (is_instance(ReQLOp, perhaps_opt_dict)) then
          opts = perhaps_opt_dict
          fields[fields.n] = nil
          fields.n = fields.n - 1
        end
      end
      for i=1, fields.n do
        fields[i] = r.expr(fields[i])
      end
      return Group(opts, self, unpack(fields))
    end,
    order_by = function(self, ...)
      -- Default if no opts dict provided
      local opts = {}
      local attrs = {...}

      -- Look for opts dict
      local perhaps_opt_dict = attrs[attrs.n]
      if (type(perhaps_opt_dict) == 'table') and not is_instance(ReQLOp, perhaps_opt_dict) then
        opts = perhaps_opt_dict
        attrs[attrs.n] = nil
        attrs.n = attrs.n - 1
      end
      for i, attr in ipairs(attrs) do
        if not (is_instance(Asc, attr) or is_instance(Desc, attr)) then
          attrs[i] = r.expr(attr)
        end
      end
      return OrderBy(opts, self, unpack(attrs))
    end,

    -- Geo operations
    to_geo_json = function(...)
      return ToGeoJson({}, ...)
    end,
    distance = function(self, g, opts)
      return Distance(opts, self, g)
    end,
    intersects = function(...)
      return Intersects({}, ...)
    end,
    includes = function(...)
      return Includes({}, ...)
    end,
    fill = function(...)
      return Fill({}, ...)
    end,
    polygon_sub = function(...)
      return PolygonSub({}, ...)
    end,

    -- Database operations

    table_create = function(self, tbl_name, opts)
      return TableCreate(opts, self, tbl_name)
    end,
    table_drop = function(...)
      return TableDrop({}, ...)
    end,
    table_list = function(...)
      return TableList({}, ...)
    end,
    table = function(self, tbl_name, opts)
      return Table(opts, self, tbl_name)
    end,

    -- Table operations

    get = function(...)
      return Get({}, ...)
    end,
    get_all = function(self, ...)
      -- Default if no opts dict provided
      local opts = {}
      local keys = {...}

      -- Look for opts dict
      if keys.n > 1 then
        local perhaps_opt_dict = keys[keys.n]
        if (type(perhaps_opt_dict) == 'table') and (not is_instance(ReQLOp, perhaps_opt_dict)) then
          opts = perhaps_opt_dict
          keys[keys.n] = nil
        end
      end
      return GetAll(opts, self, unpack(keys))
    end,
    insert = function(self, doc, opts)
      return Insert(opts, self, r.expr(doc))
    end,
    index_create = function(self, name, defun_or_opts, opts)
      if opts then
        return IndexCreate(opts, self, name, r.expr(defun_or_opts))
      end
      if defun_or_opts then
        if (type(defun_or_opts) == 'table') and (not is_instance(ReQLOp, defun_or_opts)) then
          return IndexCreate(defun_or_opts, self, name)
        end
        return IndexCreate({}, self, name, r.expr(defun_or_opts))
      end
      return IndexCreate({}, self, name)
    end,
    index_drop = function(...)
      return IndexDrop({}, ...)
    end,
    index_list = function(...)
      return IndexList({}, ...)
    end,
    index_status = function(...)
      return IndexStatus({}, ...)
    end,
    index_wait = function(...)
      return IndexWait({}, ...)
    end,
    index_rename = function(self, old_name, new_name, opts)
      return IndexRename(opts, self, old_name, new_name)
    end,
    sync = function(...)
      return Sync({}, ...)
    end,
    to_iso8601 = function(...)
      return ToISO8601({}, ...)
    end,
    to_epoch_time = function(...)
      return ToEpochTime({}, ...)
    end,
    in_timezone = function(...)
      return InTimezone({}, ...)
    end,
    during = function(self, t2, t3, opts)
      return During(opts, self, t2, t3)
    end,
    date = function(...)
      return Date({}, ...)
    end,
    time_of_day = function(...)
      return TimeOfDay({}, ...)
    end,
    timezone = function(...)
      return Timezone({}, ...)
    end,
    year = function(...)
      return Year({}, ...)
    end,
    month = function(...)
      return Month({}, ...)
    end,
    day = function(...)
      return Day({}, ...)
    end,
    day_of_week = function(...)
      return DayOfWeek({}, ...)
    end,
    day_of_year = function(...)
      return DayOfYear({}, ...)
    end,
    hours = function(...)
      return Hours({}, ...)
    end,
    minutes = function(...)
      return Minutes({}, ...)
    end,
    seconds = function(...)
      return Seconds({}, ...)
    end,
    uuid = function(...)
      return UUID({}, ...)
    end,
    get_intersecting = function(self, g, opts)
      return GetIntersecting(opts, self, g)
    end,
    get_nearest = function(self, g, opts)
      return GetNearest(opts, self, g)
    end
  }
)

local meta = {
  __call = function(...)
    return Bracket({}, ...)
  end,
  __add = function(...)
    return Add({}, ...)
  end,
  __mul = function(...)
    return Mul({}, ...)
  end,
  __mod = function(...)
    return Mod({}, ...)
  end,
  __sub = function(...)
    return Sub({}, ...)
  end,
  __div = function(...)
    return Div({}, ...)
  end
}

function ast(name, base)
  for k, v in pairs(meta) do
    base[k] = v
  end
  return class(name, ReQLOp, base)
end

DatumTerm = ast(
  'DatumTerm',
  {
    __init = function(self, val)
      self.data = val
    end,
    args = {},
    optargs = {},
    compose = function(self)
      if type(self.data) == 'string' then
        return '"' .. self.data .. '"'
      end
      if self.data == nil then
        return 'nil'
      end
      return '' .. self.data
    end,
    build = function(self)
      if type(self.data) == 'number' then
        if math.abs(self.data) == 1/0 or self.data == ((1/0) * 0) then
          error('Illegal non-finite number `' .. self.data .. '`.')
        end
      end
      if self.data == nil then return json.util.null end
      return self.data
    end
  }
)

MakeArray = ast('MakeArray', {tt = 2, st = '{...}'})
MakeObj = ast('MakeObj', {tt = 3, st = 'make_obj'})
Var = ast('Var', {tt = 10, st = 'var'})
JavaScript = ast('JavaScript', {tt = 11, st = 'js'})
Http = ast('Http', {tt = 153, st = 'http'})
Json = ast('Json', {tt = 98, st = 'json'})
Binary = ast('Binary', {tt = 155, st = 'binary'})
Args = ast('Args', {tt = 154, st = 'args'})
Error = ast('Error', {tt = 12, st = 'error'})
Random = ast('Random', {tt = 151, st = 'random'})
Db = ast('Db', {tt = 14, st = 'db'})
Table = ast('Table', {tt = 15, st = 'table'})
Get = ast('Get', {tt = 16, st = 'get'})
GetAll = ast('GetAll', {tt = 78, st = 'get_all'})
Eq = ast('Eq', {tt = 17, st = 'eq'})
Ne = ast('Ne', {tt = 18, st = 'ne'})
Lt = ast('Lt', {tt = 19, st = 'lt'})
Le = ast('Le', {tt = 20, st = 'le'})
Gt = ast('Gt', {tt = 21, st = 'gt'})
Ge = ast('Ge', {tt = 22, st = 'ge'})
Not = ast('Not', {tt = 23, st = 'not_'})
Add = ast('Add', {tt = 24, st = 'add'})
Sub = ast('Sub', {tt = 25, st = 'sub'})
Mul = ast('Mul', {tt = 26, st = 'mul'})
Div = ast('Div', {tt = 27, st = 'div'})
Mod = ast('Mod', {tt = 28, st = 'mod'})
Append = ast('Append', {tt = 29, st = 'append'})
Prepend = ast('Prepend', {tt = 80, st = 'prepend'})
Difference = ast('Difference', {tt = 95, st = 'difference'})
SetInsert = ast('SetInsert', {tt = 88, st = 'set_insert'})
SetUnion = ast('SetUnion', {tt = 90, st = 'set_union'})
SetIntersection = ast('SetIntersection', {tt = 89, st = 'set_intersection'})
SetDifference = ast('SetDifference', {tt = 91, st = 'set_difference'})
Slice = ast('Slice', {tt = 30, st = 'slice'})
Skip = ast('Skip', {tt = 70, st = 'skip'})
Limit = ast('Limit', {tt = 71, st = 'limit'})
GetField = ast('GetField', {tt = 31, st = 'get_field'})
Bracket = ast('Bracket', {tt = 170, st = '(...)'})
Contains = ast('Contains', {tt = 93, st = 'contains'})
InsertAt = ast('InsertAt', {tt = 82, st = 'insert_at'})
SpliceAt = ast('SpliceAt', {tt = 85, st = 'splice_at'})
DeleteAt = ast('DeleteAt', {tt = 83, st = 'delete_at'})
ChangeAt = ast('ChangeAt', {tt = 84, st = 'change_at'})
Contains = ast('Contains', {tt = 93, st = 'contains'})
HasFields = ast('HasFields', {tt = 32, st = 'has_fields'})
WithFields = ast('WithFields', {tt = 96, st = 'with_fields'})
Keys = ast('Keys', {tt = 94, st = 'keys'})
Changes = ast('Changes', {tt = 152, st = 'changes'})
Object = ast('Object', {tt = 143, st = 'object'})
Pluck = ast('Pluck', {tt = 33, st = 'pluck'})
IndexesOf = ast('IndexesOf', {tt = 87, st = 'indexes_of'})
Without = ast('Without', {tt = 34, st = 'without'})
Merge = ast('Merge', {tt = 35, st = 'merge'})
Between = ast('Between', {tt = 36, st = 'between'})
Reduce = ast('Reduce', {tt = 37, st = 'reduce'})
Map = ast('Map', {tt = 38, st = 'map'})
Filter = ast('Filter', {tt = 39, st = 'filter'})
ConcatMap = ast('ConcatMap', {tt = 40, st = 'concat_map'})
OrderBy = ast('OrderBy', {tt = 41, st = 'order_by'})
Distinct = ast('Distinct', {tt = 42, st = 'distinct'})
Count = ast('Count', {tt = 43, st = 'count'})
Union = ast('Union', {tt = 44, st = 'union'})
Nth = ast('Nth', {tt = 45, st = 'nth'})
ToJsonString = ast('ToJsonString', {tt = 172, st = 'to_json_string'})
Match = ast('Match', {tt = 97, st = 'match'})
Split = ast('Split', {tt = 149, st = 'split'})
Upcase = ast('Upcase', {tt = 141, st = 'upcase'})
Downcase = ast('Downcase', {tt = 142, st = 'downcase'})
IsEmpty = ast('IsEmpty', {tt = 86, st = 'is_empty'})
Group = ast('Group', {tt = 144, st = 'group'})
Sum = ast('Sum', {tt = 145, st = 'sum'})
Avg = ast('Avg', {tt = 146, st = 'avg'})
Min = ast('Min', {tt = 147, st = 'min'})
Max = ast('Max', {tt = 148, st = 'max'})
InnerJoin = ast('InnerJoin', {tt = 48, st = 'inner_join'})
OuterJoin = ast('OuterJoin', {tt = 49, st = 'outer_join'})
EqJoin = ast('EqJoin', {tt = 50, st = 'eq_join'})
Zip = ast('Zip', {tt = 72, st = 'zip'})
CoerceTo = ast('CoerceTo', {tt = 51, st = 'coerce_to'})
Ungroup = ast('Ungroup', {tt = 150, st = 'ungroup'})
TypeOf = ast('TypeOf', {tt = 52, st = 'type_of'})
Info = ast('Info', {tt = 79, st = 'info'})
Sample = ast('Sample', {tt = 81, st = 'sample'})
Update = ast('Update', {tt = 53, st = 'update'})
Delete = ast('Delete', {tt = 54, st = 'delete'})
Replace = ast('Replace', {tt = 55, st = 'replace'})
Insert = ast('Insert', {tt = 56, st = 'insert'})
DbCreate = ast('DbCreate', {tt = 57, st = 'db_create'})
DbDrop = ast('DbDrop', {tt = 58, st = 'db_drop'})
DbList = ast('DbList', {tt = 59, st = 'db_list'})
TableCreate = ast('TableCreate', {tt = 60, st = 'table_create'})
TableDrop = ast('TableDrop', {tt = 61, st = 'table_drop'})
TableList = ast('TableList', {tt = 62, st = 'table_list'})
IndexCreate = ast('IndexCreate', {tt = 75, st = 'index_create'})
IndexDrop = ast('IndexDrop', {tt = 76, st = 'index_drop'})
IndexRename = ast('IndexRename', {tt = 156, st = 'index_rename'})
IndexList = ast('IndexList', {tt = 77, st = 'index_list'})
IndexStatus = ast('IndexStatus', {tt = 139, st = 'index_status'})
IndexWait = ast('IndexWait', {tt = 140, st = 'index_wait'})
Sync = ast('Sync', {tt = 138, st = 'sync'})
FunCall = ast('FunCall', {tt = 64, st = 'do_'})
Default = ast('Default', {tt = 92, st = 'default'})
Branch = ast('Branch', {tt = 65, st = 'branch'})
Any = ast('Any', {tt = 66, st = 'any'})
All = ast('All', {tt = 67, st = 'all'})
ForEach = ast('ForEach', {tt = 68, st = 'for_each'})
Func = ast('Func', {tt = 69, st = 'func'})
Asc = ast('Asc', {tt = 73, st = 'asc'})
Desc = ast('Desc', {tt = 74, st = 'desc'})
Literal = ast('Literal', {tt = 137, st = 'literal'})
ISO8601 = ast('ISO8601', {tt = 99, st = 'iso8601'})
ToISO8601 = ast('ToISO8601', {tt = 100, st = 'to_iso8601'})
EpochTime = ast('EpochTime', {tt = 101, st = 'epoch_time'})
ToEpochTime = ast('ToEpochTime', {tt = 102, st = 'to_epoch_time'})
Now = ast('Now', {tt = 103, st = 'now'})
InTimezone = ast('InTimezone', {tt = 104, st = 'in_timezone'})
During = ast('During', {tt = 105, st = 'during'})
Date = ast('Date', {tt = 106, st = 'date'})
TimeOfDay = ast('TimeOfDay', {tt = 126, st = 'time_of_day'})
Timezone = ast('Timezone', {tt = 127, st = 'timezone'})
Year = ast('Year', {tt = 128, st = 'year'})
Month = ast('Month', {tt = 129, st = 'month'})
Day = ast('Day', {tt = 130, st = 'day'})
DayOfWeek = ast('DayOfWeek', {tt = 131, st = 'day_of_week'})
DayOfYear = ast('DayOfYear', {tt = 132, st = 'day_of_year'})
Hours = ast('Hours', {tt = 133, st = 'hours'})
Minutes = ast('Minutes', {tt = 134, st = 'minutes'})
Seconds = ast('Seconds', {tt = 135, st = 'seconds'})
Time = ast('Time', {tt = 136, st = 'time'})
GeoJson = ast('GeoJson', {tt = 157, st = 'geo_json'})
ToGeoJson = ast('ToGeoJson', {tt = 158, st = 'to_geo_json'})
Point = ast('Point', {tt = 159, st = 'point'})
Line = ast('Line', {tt = 160, st = 'line'})
Polygon = ast('Polygon', {tt = 161, st = 'polygon'})
Distance = ast('Distance', {tt = 162, st = 'distance'})
Intersects = ast('Intersects', {tt = 163, st = 'intersects'})
Includes = ast('Includes', {tt = 164, st = 'includes'})
Circle = ast('Circle', {tt = 165, st = 'circle'})
GetIntersecting = ast('GetIntersecting', {tt = 166, st = 'get_intersecting'})
GetNearest = ast('GetNearest', {tt = 168, st = 'get_nearest'})
Fill = ast('Fill', {tt = 167, st = 'fill'})
PolygonSub = ast('PolygonSub', {tt = 171, st = 'polygon_sub'})
UUID = ast('UUID', {tt = 169, st = 'uuid'})

-- All top level exported functions

-- Wrap a native Lua value in an ReQL datum
function r.expr(val, nesting_depth)
  if nesting_depth == nil then
    nesting_depth = 20
  end
  if nesting_depth <= 0 then
    error(ReQLDriverError('Nesting depth limit exceeded'))
  end
  if type(nesting_depth) ~= 'number' then
    error(ReQLDriverError('Second argument to `r.expr` must be a number or nil.'))
  end
  if is_instance(ReQLOp, val) then
    return val
  end
  if type(val) == 'function' then
    return Func({}, val)
  end
  if type(val) == 'table' then
    local array = true
    for k, v in pairs(val) do
      if type(k) ~= 'number' then array = false end
      val[k] = r.expr(v, nesting_depth - 1)
    end
    if array then
      return MakeArray({}, val)
    end
    return MakeObj(val)
  end
  return DatumTerm(val)
end
function r.js(jssrc, opts)
  return JavaScript(opts, jssrc)
end
function r.http(url, opts)
  return Http(opts, url)
end
function r.json(...)
  return Json({}, ...)
end
function r.error(...)
  return Error({}, ...)
end
function r.random(...)
  -- Default if no opts dict provided
  local opts = {}
  local limits = {...}

  -- Look for opts dict
  local perhaps_opt_dict = limits[limits.n]
  if (type(perhaps_opt_dict) == 'table') and (not is_instance(ReQLOp, perhaps_opt_dict)) then
    opts = perhaps_opt_dict
    limits[limits.n] = nil
  end
  return Random(opts, unpack(limits))
end
function r.binary(data)
  return Binary(data)
end
function r.table(tbl_name, opts)
  return Table(opts, tbl_name)
end
function r.db(...)
  return Db({}, ...)
end
function r.db_create(...)
  return DbCreate({}, ...)
end
function r.db_drop(...)
  return DbDrop({}, ...)
end
function r.db_list(...)
  return DbList({}, ...)
end
function r.table_create(tbl_name, opts)
  return TableCreate(opts, tbl_name)
end
function r.table_drop(...)
  return TableDrop({}, ...)
end
function r.table_list(...)
  return TableList({}, ...)
end
function r.do_(...)
  args = {...}
  func = Func({arity = args.n - 1}, args[args.n])
  args[args.n] = nil
  return FunCall({}, func, unpack(args))
end
function r.branch(...)
  return Branch({}, ...)
end
function r.asc(...)
  return Asc({}, ...)
end
function r.desc(...)
  return Desc({}, ...)
end
function r.eq(...)
  return Eq({}, ...)
end
function r.ne(...)
  return Ne({}, ...)
end
function r.lt(...)
  return Lt({}, ...)
end
function r.le(...)
  return Le({}, ...)
end
function r.gt(...)
  return Gt({}, ...)
end
function r.ge(...)
  return Ge({}, ...)
end
function r.or_(...)
  return Any({}, ...)
end
function r.any(...)
  return Any({}, ...)
end
function r.and_(...)
  return All({}, ...)
end
function r.all(...)
  return All({}, ...)
end
function r.not_(...)
  return Not({}, ...)
end
function r.add(...)
  return Add({}, ...)
end
function r.sub(...)
  return Sub({}, ...)
end
function r.div(...)
  return Div({}, ...)
end
function r.mul(...)
  return Mul({}, ...)
end
function r.mod(...)
  return Mod({}, ...)
end
function r.type_of(...)
  return TypeOf({}, ...)
end
function r.info(...)
  return Info({}, ...)
end
function r.literal(...)
  return Literal({}, ...)
end
function r.iso8601(str, opts)
  return ISO8601(opts, str)
end
function r.epoch_time(...)
  return EpochTime({}, ...)
end
function r.now(...)
  return Now({}, ...)
end
function r.time(...)
  return Time({}, ...)
end

r.monday = ast('Monday', {tt = 107, st = 'monday'})()
r.tuesday = ast('Tuesday', {tt = 108, st = 'tuesday'})()
r.wednesday = ast('Wednesday', {tt = 109, st = 'wednesday'})()
r.thursday = ast('Thursday', {tt = 110, st = 'thursday'})()
r.friday = ast('Friday', {tt = 111, st = 'friday'})()
r.saturday = ast('Saturday', {tt = 112, st = 'saturday'})()
r.sunday = ast('Sunday', {tt = 113, st = 'sunday'})()

r.january = ast('January', {tt = 114, st = 'january'})()
r.february = ast('February', {tt = 115, st = 'february'})()
r.march = ast('March', {tt = 116, st = 'march'})()
r.april = ast('April', {tt = 117, st = 'april'})()
r.may = ast('May', {tt = 118, st = 'may'})()
r.june = ast('June', {tt = 119, st = 'june'})()
r.july = ast('July', {tt = 120, st = 'july'})()
r.august = ast('August', {tt = 121, st = 'august'})()
r.september = ast('September', {tt = 122, st = 'september'})()
r.october = ast('October', {tt = 123, st = 'october'})()
r.november = ast('November', {tt = 124, st = 'november'})()
r.december = ast('December', {tt = 125, st = 'december'})()

function r.object(...)
  return Object({}, ...)
end
function r.args(...)
  return Args({}, ...)
end
function r.geo_json(...)
  return GeoJson({}, ...)
end
function r.point(...)
  return Point({}, ...)
end
function r.line(...)
  return Line({}, ...)
end
function r.polygon(...)
  return Polygon({}, ...)
end
function r.intersects(...)
  return Intersects({}, ...)
end
function r.distance(g1, g2, opts)
  return Distance(opts, g1, g2)
end
function r.circle(cen, rad, opts)
  return Circle(opts, cen, rad)
end
function r.uuid(...)
  return UUID({}, ...)
end

function bytes_to_int(str)
  local t = {str:byte(1,-1)}
  local n = 0
  for k=1,#t do
    n = n + t[k] * 2 ^ ((k - 1) * 8)
  end
  return n
end

function div_mod(num, den)
  return math.floor(num / den), math.fmod(num, den)
end

function int_to_bytes(num, bytes)
  local res = {}
  local mul = 0
  for k=bytes,1,-1 do
    res[k], num = div_mod(num, 2 ^ (8 * (k - 1)))
  end
  return string.char(unpack(res))
end

function convert_pseudotype(obj, opts)
  -- An R_OBJECT may be a regular object or a 'pseudo-type' so we need a
  -- second layer of type switching here on the obfuscated field '$reql_type$'
  local _exp_0 = obj['$reql_type$']
  if 'TIME' == _exp_0 then
    local _exp_1 = opts.time_format
    if 'native' == _exp_1 or not _exp_1 then
      if not (obj['epoch_time']) then
        error(err.ReQLDriverError('pseudo-type TIME ' .. tostring(obj) .. ' object missing expected field `epoch_time`.'))
      end

      -- We ignore the timezone field of the pseudo-type TIME object. JS dates do not support timezones.
      -- By converting to a native date object we are intentionally throwing out timezone information.

      -- field 'epoch_time' is in seconds but the Date constructor expects milliseconds
      return (Date(obj['epoch_time'] * 1000))
    elseif 'raw' == _exp_1 then
      -- Just return the raw (`{'$reql_type$'...}`) object
      return obj
    else
      error(err.ReQLDriverError('Unknown time_format run option ' .. tostring(opts.time_format) .. '.'))
    end
  elseif 'GROUPED_DATA' == _exp_0 then
    local _exp_1 = opts.group_format
    if 'native' == _exp_1 or not _exp_1 then
      -- Don't convert the data into a map, because the keys could be objects which doesn't work in JS
      -- Instead, we have the following format:
      -- [ { 'group': <group>, 'reduction': <value(s)> } }, ... ]
      res = {}
      j = 1
      for i, v in ipairs(obj['data']) do
        res[j] = {
          group = i,
          reduction = v
        }
        j = j + 1
      end
      obj = res
    elseif 'raw' == _exp_1 then
      return obj
    else
      error(err.ReQLDriverError('Unknown group_format run option ' .. tostring(opts.group_format) .. '.'))
    end
  elseif 'BINARY' == _exp_0 then
    local _exp_1 = opts.binary_format
    if 'native' == _exp_1 or not _exp_1 then
      if not obj.data then
        error(err.ReQLDriverError('pseudo-type BINARY object missing expected field `data`.'))
      end
      return (mime.unb64(obj.data))
    elseif 'raw' == _exp_1 then
      return obj
    else
      error(err.ReQLDriverError('Unknown binary_format run option ' .. tostring(opts.binary_format) .. '.'))
    end
  else
    -- Regular object or unknown pseudo type
    return obj
  end
end

function recursively_convert_pseudotype(obj, opts)
  if type(obj) == 'table' then
    for key, value in pairs(obj) do
      obj[key] = recursively_convert_pseudotype(value, opts)
    end
    obj = convert_pseudotype(obj, opts)
  end
  if obj == json.util.null then return nil end
  return obj
end

Cursor = class(
  'Cursor',
  {
    __init = function(self, conn, token, opts, root)
      self._conn = conn
      self._token = token
      self._opts = opts
      self._root = root -- current query
      self._responses = {}
      self._response_index = 1
      self._cont_flag = true
    end,
    _add_response = function(self, response)
      local t = response.t
      if not self._type then self._type = t end
      if response.r[1] or t == 4 then
        table.insert(self._responses, response)
      end
      if t ~= 3 and t ~= 5 then
        -- We got an error, SUCCESS_SEQUENCE, WAIT_COMPLETE, or a SUCCESS_ATOM
        self._end_flag = true
        self._conn:_del_query(self._token)
      end
      self._cont_flag = false
    end,
    _prompt_cont = function(self)
      if self._end_flag then return end
      -- Let's ask the server for more data if we haven't already
      if not self._cont_flag then
        self._cont_flag = true
        self._conn:_continue_query(self._token)
      end
      self._conn:_get_response(self._token)
    end,
    -- Implement IterableResult
    next = function(self, cb)
      -- Try to get a row out of the responses
      while not self._responses[1] do
        if self._end_flag then
          return cb(ReQLDriverError('No more rows in the cursor.'))
        end
        self:_prompt_cont()
      end
      local response = self._responses[1]
      -- Behavior varies considerably based on response type
      -- Error responses are not discarded, and the error will be sent to all future callbacks
      local t = response.t
      if t == 1 or t == 3 or t == 5 or t == 2 then
        local row = recursively_convert_pseudotype(response.r[self._response_index], self._opts)
        self._response_index = self._response_index + 1

        -- If we're done with this response, discard it
        if not response.r[self._response_index] then
          table.remove(self._responses, 1)
          self._response_index = 1
        end
        return cb(nil, row)
      elseif t == 17 then
        return cb(ReQLCompileError(response.r[1], self._root, response.b))
      elseif t == 16 then
        return cb(ReQLClientError(response.r[1], self._root, response.b))
      elseif t == 18 then
        return cb(ReQLRuntimeError(response.r[1], self._root, response.b))
      elseif t == 4 then
        return cb(nil, nil)
      end
      return cb(ReQLDriverError('Unknown response type ' .. t))
    end,
    close = function(self, cb)
      if not self._end_flag then
        self._conn:_end_query(self._token)
      end
      if cb then return cb() end
    end,
    each = function(self, cb, on_finished)
      if type(cb) ~= 'function' then
        error(ReQLDriverError('First argument to each must be a function.'))
      end
      if on_finished and type(on_finished) ~= 'function' then
        error(ReQLDriverError('Optional second argument to each must be a function.'))
      end
      function next_cb(err, data)
        if err then
          if err.message ~= 'ReQLDriverError No more rows in the cursor.' then
            return cb(err)
          end
          if on_finished then
            return on_finished()
          end
        else
          cb(nil, data)
          return self:next(next_cb)
        end
      end
      return self:next(next_cb)
    end,
    to_array = function(self, cb)
      if not self._type then self:_prompt_cont() end
      if self._type == 5 then
        return cb(ReQLDriverError('`to_array` is not available for feeds.'))
      end
      local arr = {}
      return self:each(
        function(err, row)
          if err then
            return cb(err)
          end
          table.insert(arr, row)
        end,
        function()
          return cb(nil, arr)
        end
      )
    end,
  }
)

Connection = class(
  'Connection',
  {
    __init = function(self, host_or_callback, callback)
      local host = {}
      if type(host_or_callback) == 'function' then
        callback = host_or_callback
      else
        host = host_or_callback
      end
      if type(host) == 'string' then
        host = {
          host = host
        }
      end
      function cb(err, conn)
        if callback then
          local res = callback(err, conn)
          conn:close({noreply_wait = false})
          return res
        end
        return conn, err
      end
      self.host = host.host or self.DEFAULT_HOST
      self.port = host.port or self.DEFAULT_PORT
      self.db = host.db -- left nil if this is not set
      self.auth_key = host.auth_key or self.DEFAULT_AUTH_KEY
      self.timeout = host.timeout or self.DEFAULT_TIMEOUT
      self.outstanding_callbacks = {}
      self.next_token = 1
      self.open = false
      self.buffer = ''
      self._events = self._events or {}
      if self.raw_socket then
        self:close({
          noreply_wait = false
        })
      end
      self.raw_socket = socket.tcp()
      self.raw_socket:settimeout(self.timeout)
      local status, err = self.raw_socket:connect(self.host, self.port)
      if status then
        local buf, err, partial
        -- Initialize connection with magic number to validate version
        self.raw_socket:send(
          int_to_bytes(1601562686, 4) ..
          int_to_bytes(self.auth_key:len(), 4) ..
          self.auth_key ..
          int_to_bytes(2120839367, 4)
        )

        -- Now we have to wait for a response from the server
        -- acknowledging the connection
        while 1 do
          buf, err, partial = self.raw_socket:receive(8)
          buf = buf or partial
          if not buf then
            return cb(ReQLDriverError('Server dropped connection with message:  \'' .. status_str .. '\'\n' .. err))
          end
          self.buffer = self.buffer .. buf
          i, j = buf:find('\0')
          if i then
            local status_str = self.buffer:sub(1, i - 1)
            self.buffer = self.buffer:sub(i + 1)
            if status_str == 'SUCCESS' then
              -- We're good, finish setting up the connection
              self.open = true
              return cb(nil, self)
            end
            return cb(ReQLDriverError('Server dropped connection with message: \'' .. status_str .. '\''))
          end
        end
      end
      return cb(ReQLDriverError('Could not connect to ' .. self.host .. ':' .. self.port .. '.\n' .. err))
    end,
    DEFAULT_HOST = 'localhost',
    DEFAULT_PORT = 28015,
    DEFAULT_AUTH_KEY = '',
    DEFAULT_TIMEOUT = 20, -- In seconds
    _get_response = function(self, reqest_token)
      local response_length = 0
      local token = 0
      local buf, err, partial
      -- Buffer data, execute return results if need be
      while true do
        buf, err, partial = self.raw_socket:receive(
          math.max(12, response_length)
        )
        buf = buf or partial
        if (not buf) and err then
          return self:_process_response(
            {
              t = 16,
              r = {'connection returned: ' .. err},
              b = {}
            },
            reqest_token
          )
        end
        self.buffer = self.buffer .. buf
        if response_length > 0 then
          if string.len(self.buffer) >= response_length then
            local response_buffer = string.sub(self.buffer, 1, response_length)
            self.buffer = string.sub(self.buffer, response_length + 1)
            response_length = 0
            self:_process_response(json.decode(response_buffer), token)
            if token == reqest_token then return end
          end
        else
          if string.len(self.buffer) >= 12 then
            token = bytes_to_int(self.buffer:sub(1, 8))
            response_length = bytes_to_int(self.buffer:sub(9, 12))
            self.buffer = self.buffer:sub(13)
          end
        end
      end
    end,
    _del_query = function(self, token)
      -- This query is done, delete this cursor
      self.outstanding_callbacks[token].cursor = nil
    end,
    _process_response = function(self, response, token)
      local cursor = self.outstanding_callbacks[token]
      if not cursor then
        -- Unexpected token
        error(ReQLDriverError('Unexpected token ' .. token .. '.'))
      end
      cursor = cursor.cursor
      if cursor then
        return cursor:_add_response(response)
      end
    end,
    close = function(self, opts_or_callback, callback)
      local opts = {}
      local cb
      if callback then
        if type(opts_or_callback) ~= 'table' then
          error(ReQLDriverError('First argument to two-argument `close` must be an object.'))
        end
        opts = opts_or_callback
        cb = callback
      else
        if type(opts_or_callback) == 'table' then
          opts = opts_or_callback
        else
          if type(opts_or_callback) == 'function' then
            cb = opts_or_callback
          end
        end
      end

      if cb and type(cb) ~= 'function' then
        error(ReQLDriverError('First argument to two-argument `close` must be an object.'))
      end

      local wrapped_cb = function(...)
        self.open = false
        self.raw_socket:shutdown()
        self.raw_socket:close()
        if cb then
          return cb(...)
        end
      end

      local noreply_wait = opts.noreply_wait and self.open

      if noreply_wait then
        return self:noreply_wait(wrapped_cb)
      end
      return wrapped_cb()
    end,
    noreply_wait = function(self, cb)
      if type(cb) ~= 'function' then
        cb = function() end
      end
      function callback(err, cur)
        if cur then
          local res = cur.next(function(err) return cb(err) end)
          cur:close()
          return res
        end
        return cb(err)
      end
      if not self.open then
        return callback(ReQLDriverError('Connection is closed.'))
      end

      -- Assign token
      local token = self.next_token
      self.next_token = self.next_token + 1

      -- Save cursor
      local cursor = Cursor(self, token, {})

      -- Save cursor
      self.outstanding_callbacks[token] = {cursor = cursor}

      -- Construct query
      self:_write_query(token, '[' .. 4 .. ']')

      return callback(nil, cursor)
    end,
    _write_query = function(self, token, data)
      self.raw_socket:send(
        int_to_bytes(token, 8) ..
        int_to_bytes(#data, 4) ..
        data
      )
    end,
    cancel = function(self)
      self.raw_socket.destroy()
      self.outstanding_callbacks = {}
    end,
    reconnect = function(self, opts_or_callback, callback)
      local opts, cb
      if callback then
        opts = opts_or_callback
        cb = callback
      else
        if type(opts_or_callback) == 'function' then
          opts = {}
          cb = opts_or_callback
        else
          if opts_or_callback then
            opts = opts_or_callback
          else
            opts = {}
          end
          cb = callback
        end
      end
      local close_cb = function(err)
        if err then
          return cb(err)
        end
        return Connection(self, cb)
      end
      return self:close(opts, close_cb)
    end,
    use = function(self, db)
      self.db = db
    end,
    _start = function(self, term, cb, opts)
      if not (self.open) then
        cb(ReQLDriverError('Connection is closed.'))
      end

      -- Assign token
      local token = self.next_token
      self.next_token = self.next_token + 1

      for k, v in pairs(opts) do
        if k == 'use_outdated' or k == 'noreply' or k == 'profile' then
          v = not not v
        end
        opts[k] = r(v):build()
      end

      -- Set global options
      if self.db then
        opts.db = r.db(self.db):build()
      end

      -- Construct query
      local query = {1, term:build(), opts}

      local cursor = Cursor(self, token, opts, term)

      -- Save cursor
      self.outstanding_callbacks[token] = {cursor = cursor}
      self:_send_query(token, query)
      if type(cb) == 'function' and not opts.noreply then
        local res = cb(nil, cursor)
        cursor:close()
        return res
      end
    end,
    _continue_query = function(self, token)
      return self:_write_query(token, '[' .. 2 .. ']')
    end,
    _end_query = function(self, token)
      return self:_write_query(token, '[' .. 3 .. ']')
    end,
    _send_query = function(self, token, query)
      return self:_write_query(token, json.encode(query))
    end
  }
)

-- Add connect
r.connect = function(...)
  return Connection(...)
end

-- Export ReQL Errors
r.error = {
  ReQLError = ReQLError,
  ReQLDriverError = ReQLDriverError,
  ReQLServerError = ReQLServerError,
  ReQLRuntimeError = ReQLRuntimeError,
  ReQLCompileError = ReQLCompileError,
  ReQLClientError = ReQLClientError
}

-- Export class introspection
r.is_instance = is_instance

-- Export all names defined on r
return r
