

local function table_eq(a,b)
    if type(a) ~= type(b) then
        return false
    end
    if a == b then
        return true
    end
    if type(a) ~= 'table' then
        return a == b
    end
    if #a ~= #b then
        return false
    end
    for k,v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    for k,v in pairs(b) do
        if a[k] ~= v then
            return false
        end
    end
    return true
end

local function var_tostring(tab)
    if type(tab) ~= 'table' then
        return tostring(tab)
    end
    local ret = ''
    for key,value in pairs(tab) do
        ret = ret..' '..key  .. '= ' .. var_tostring(value) .. ', '
    end
    return '{'..ret..'}'
end

-- FAIL TEST AND STOP EXECUTION
local failure_prefix = "[TEST FAILED] "
local function fail_test(reason, ...)
    local complex = {...}
    local strings = {}
    for _,var in ipairs(complex) do 
        table.insert(strings, var_tostring(var))
    end
    error(failure_prefix..reason:format(unpack(strings)))
end

-- STUBS
local stubs = {}
local function stub()
    local calls = {}
    local stub_api = {
        reset = function ()
            calls = {}
        end,
        pub = {
            call = function (...)
                table.insert(calls, {...})
            end,
            called_with = function (...)
                local args = {...}
                for _,call_args in ipairs(calls) do
                    if table_eq(args, call_args) then
                        return true
                    end
                end

                fail_test("gravelsieve.log was not called with args: "..var_tostring(args))
            end,
            called_times = function (n)
                if n ~= #calls then
                    fail_test("gravelsieve.log was called %s times, not %s times", #calls, n)
                end
            end,
        }
    }
    table.insert(stubs, stub_api)
    return stub_api.pub
end

local function reset_stubs()
    for _,stub_api in ipairs(stubs) do
        stub_api.reset()
    end
end

-- EXPECTATIONS
local expected_error = false
local function expect_error(message)
    if not message then
        expected_error = true
    else
        expected_error = message
    end
end

local function reset_expectations()
    expected_error = false
end

-- ASSERTIONS
local function assert_equal(a,b,message)
    if not table_eq(a,b) then
        if not message then message = "Values should be equal." end
        fail_test(message.." Expected %s, got %s.", a, b)
    end
end
local function assert_not_equal(a,b,message)
   if table_eq(a,b) then
        if not message then message = "Values should not be equal." end
        fail_test(message.." Did not expect %s.", b)
    end 
end


-- ACTUAL TESTING PROCESS FUNCTIONS

local failed_tests = {}
local function record_failure(test_description, info)
    table.insert(failed_tests, {
        test = test_description,
        info = info or {}
    })
end

local passed_tests = {}
local function record_success(test_description)
    table.insert(passed_tests, {
        test = test_description
    })
end

local function test(current_test)
    -- EXECUTE A TEST AND HANDLE ERRORS
    local success, err = pcall(current_test.process)
    if success then
        if expected_error then
            local info = { "Error expected but none occurred" }
            if type(expected_error) == 'string' then
                table.insert(info, "Expected: "..expected_error)
            end
            record_failure(current_test, info)
        else
            record_success(current_test)
        end
    else
        if string.find(err, failure_prefix, 1, true) then
            record_failure(current_test, { err })
        elseif not expected_error then
            record_failure(current_test, {
                "Error occurred but none expected",
                "Occurred: "..err
            })
        else
            if type(expected_error) == 'string' and not string.find(err, expected_error, 1, true) then
                record_failure(current_test, {
                    "Error occurred was not the one expected",
                    "Expected: "..expected_error,
                    "Occurred: "..err
                })
            else
                record_success(current_test)
            end
        end
    end
end

local describe_id = 0
local test_descriptions = {}
local description_construct = {}
local callback_construct = {}
local function describe(description, process)
    -- DESCRIBE A GROUP OF TESTS
    describe_id = describe_id + 1
    table.insert(description_construct, description)
    table.insert(callback_construct, {
        describe_id = describe_id,
        before_each = {},
        after_each = {},
        before_all = {},
        after_all = {}
    })
    process()
    table.remove(description_construct)
    table.remove(callback_construct)
end

local function it(message, process)
    -- DESCRIBE A SINGLE TEST CASE
    local description_string = "[TESTS]"
    for i,component in ipairs(description_construct) do
        description_string = description_string .. " [" .. component .. "]"
    end
    table.insert(test_descriptions, {
        description_string = description_string,
        desc = table.copy(description_construct),
        callbacks = table.copy(callback_construct),
        message = message,
        process = process
    })
end

local function execute()
    -- EXECUTE ALL TESTS

    if #test_descriptions == 0 then
        minetest.log("[TESTS] No tests")
        return
    end
    -- Make a dud test to make sure the after_all functions get called
    table.insert(test_descriptions, {
        description_string = "[TESTS] -- END --",
        desc = {},
        callbacks = {},
        message = "",
        process = function()end
    })
    failed_tests = {}
    passed_tests = {}
    local describe_list = {}
    local prev_callbacks = {}
    for _,test_description in ipairs(test_descriptions) do

        minetest.log(test_description.description_string.." "..test_description.message)

        reset_stubs()
        reset_expectations()

        local new_describe_list = {}
        for _,callbacks in ipairs(test_description.callbacks) do
            table.insert(new_describe_list, callbacks.describe_id)
        end
        for i=math.max(#describe_list, #new_describe_list),1,-1 do
            -- if missing from new or changed, do after_all
            if not new_describe_list[i]
               or (describe_list[i] and new_describe_list[i] ~= describe_list[i]) then
                for _,callback in ipairs(prev_callbacks[i].after_all) do
                    callback()
                end
            end
        end
        for i=math.max(#describe_list, #new_describe_list),1,-1 do
            -- if missing from old or changed, do before_all
            if not describe_list[i] or (new_describe_list[i] and new_describe_list[i] ~= describe_list[i]) then
                for _,callback in ipairs(test_description.callbacks[i].before_all) do
                    callback()
                end
            end
        end

        for _,callbacks in ipairs(test_description.callbacks) do
            for i,callback in ipairs(callbacks.before_each) do
                callback()
            end
        end

        test(test_description)

        for _,callbacks in ipairs(test_description.callbacks) do
            for i,callback in ipairs(callbacks.after_each) do
                callback()
            end
        end

        prev_callbacks = test_description.callbacks
        describe_list = new_describe_list
    end
    if #failed_tests == 0 then
        minetest.log("[TESTS] all tests passed")
    else
        for _,test in ipairs(failed_tests) do
            local prefix = test.test.description_string.." "
            minetest.log("error", prefix..test.test.message)
            for _,msg in ipairs(test.info) do
                minetest.log("error", prefix..msg)
            end
        end
    end
    test_descriptions = {}
    description_construct = {}
    callback_construct = {}
    stubs = {}
end

local function before_each(callback)
    local last_construct = callback_construct[#callback_construct]
    table.insert(last_construct.before_each, callback)
end
local function after_each(callback)
    local last_construct = callback_construct[#callback_construct]
    table.insert(last_construct.after_each, callback)
end
local function before_all(callback)
    local last_construct = callback_construct[#callback_construct]
    table.insert(last_construct.before_all, callback)
end
local function after_all(callback)
    local last_construct = callback_construct[#callback_construct]
    table.insert(last_construct.after_all, callback)
end

tests = {
    describe = describe,
    it = it,
    stub = stub,
    after_each = after_each,
    before_each = before_each,
    after_all = after_all,
    before_all = before_all,
    assert = {
        equal = assert_equal,
        not_equal = assert_not_equal
    },
    expect = {
        error = expect_error
    },
    execute = execute
}