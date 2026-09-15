--!strict

-- verifies Promily core behavior, cancellation, combinators, and Roblox adapters

local replicatedStorage = game:GetService("ReplicatedStorage")

local promily = require(replicatedStorage:WaitForChild("Promily"))

--————————————————————————————————————————————————————————————————————--

type TestCallback = () -> ()
type TestSuite = {[string]: TestCallback}

local tests: TestSuite = {}

--————————————————————————————————————————————————————————————————————--

local function expectEqual(actual: any, expected: any, message: string?)
	if actual == expected then return end

	error(message or `Expected {tostring(expected)}, received {tostring(actual)}.`, 2)
end

--————————————————————————————————————————————————————————————————————--

local function expectTrue(value: boolean, message: string?)
	if value then return end

	error(message or "Expected value to be true.", 2)
end

--————————————————————————————————————————————————————————————————————--

function tests.resolveAndThen()
	local value = promily.resolve(5)
		.andThen(function(current: number): number
			return current * 2
		end)
		.expect()

	expectEqual(value, 10)
end

--————————————————————————————————————————————————————————————————————--

function tests.rejectionRecovery()
	local rejectedPromise: promily.promise<number> = promily.reject("failure")

	local value = rejectedPromise
		.catch(function(reason: any): number
			expectEqual(reason, "failure")

			return 12
		end)
		.expect()

	expectEqual(value, 12)
end

--————————————————————————————————————————————————————————————————————--

function tests.finallyPreservesValue()
	local cleanupCount = 0

	local value = promily.resolve("done")
		.finally(function()
			cleanupCount += 1
		end)
		.expect()

	expectEqual(value, "done")
	expectEqual(cleanupCount, 1)
end

--————————————————————————————————————————————————————————————————————--

function tests.cancellationCleanup()
	local cleanupCount = 0
	local started: promily.deferred<boolean> = promily.defer()

	local promiseValue = promily.new(function(_resolve, _reject, onCancel)
		onCancel(function(_reason)
			cleanupCount += 1
		end)

		started.resolve(true)
	end)

	started.promise.expect()

	expectTrue(promiseValue.cancel("test"))

	local settledStatus, reason = promiseValue.awaitStatus()

	expectEqual(settledStatus, promily.status.cancelled)
	expectEqual(reason, "test")
	expectEqual(cleanupCount, 1)
end

--————————————————————————————————————————————————————————————————————--

function tests.cancellationSource()
	local source = promily.createCancellationSource()
	local promiseValue = promily.never(source.getToken())

	source.cancel("scope")

	local settledStatus, reason = promiseValue.awaitStatus()

	expectEqual(settledStatus, promily.status.cancelled)
	expectEqual(reason, "scope")

	source.delete()
end

--————————————————————————————————————————————————————————————————————--

function tests.scopeCancellation()
	local scope = promily.createScope()

	local promiseValue = scope.newPromise(function(_resolve, _reject, onCancel)
		local timer = task.delay(10, function() end)

		onCancel(function(_reason)
			task.cancel(timer)
		end)
	end)

	expectEqual(scope.getCount(), 1)

	scope.cancel("closed")

	local settledStatus, reason = promiseValue.awaitStatus()

	expectEqual(settledStatus, promily.status.cancelled)
	expectEqual(reason, "closed")

	scope.delete()
end

--————————————————————————————————————————————————————————————————————--

function tests.all()
	local values = promily.all({
		promily.resolve(1),
		2,
		promily.resolve(3).delay(.001),
	}).expect()

	expectEqual(values[1], 1)
	expectEqual(values[2], 2)
	expectEqual(values[3], 3)
end

--————————————————————————————————————————————————————————————————————--

function tests.allSettled()
	local results = promily.allSettled({
		promily.resolve("yes"),
		promily.reject("no"),
		promily.cancelled("stop"),
	}).expect()

	expectEqual(results[1].status, promily.status.resolved)
	expectEqual(results[2].status, promily.status.rejected)
	expectEqual(results[3].status, promily.status.cancelled)
end

--————————————————————————————————————————————————————————————————————--

function tests.any()
	local value = promily.any({
		promily.reject("one"),
		promily.resolve("two").delay(.001),
	}).expect()

	expectEqual(value, "two")
end

--————————————————————————————————————————————————————————————————————--

function tests.some()
	local values = promily.some({
		promily.resolve(1).delay(.001),
		promily.resolve(2),
		promily.reject("ignored"),
	}, 2).expect()

	expectEqual(#values, 2)
end

--————————————————————————————————————————————————————————————————————--

function tests.props()
	local values = promily.props({
		first = promily.resolve(10),
		second = 20,
	}).expect()

	expectEqual(values.first, 10)
	expectEqual(values.second, 20)
end

--————————————————————————————————————————————————————————————————————--

function tests.mapConcurrency()
	local active = 0
	local maximumActive = 0

	local results = promily.map(
		{1, 2, 3, 4, 5},

		function(value: number)
			active += 1
			maximumActive = math.max(maximumActive, active)

			return promily.resolve(value * 2)
				.delay(.001)
				.finally(function()
					active -= 1
				end)
		end,

		{
			concurrency = 2,
		}
	).expect()

	expectTrue(maximumActive <= 2)
	expectEqual(results[5], 10)
end

--————————————————————————————————————————————————————————————————————--

function tests.sequence()
	local order: {number} = {}

	local results = promily.sequence({
		function()
			order[#order + 1] = 1

			return promily.resolve("a").delay(.001)
		end,

		function()
			order[#order + 1] = 2

			return "b"
		end,
	}).expect()

	expectEqual(order[1], 1)
	expectEqual(order[2], 2)
	expectEqual(results[1], "a")
	expectEqual(results[2], "b")
end

--————————————————————————————————————————————————————————————————————--

function tests.reduce()
	local total = promily.reduce(
		{1, 2, 3, 4},

		function(accumulator: number, value: number): number
			return accumulator + value
		end,

		0
	).expect()

	expectEqual(total, 10)
end

--————————————————————————————————————————————————————————————————————--

function tests.timeout()
	local settledStatus = promily.never()
		.timeout(.001)
		.awaitStatus()

	expectEqual(settledStatus, promily.status.rejected)
end

--————————————————————————————————————————————————————————————————————--

function tests.timeoutFallback()
	local value = promily.timeoutOr(
		promily.never(),
		.001,
		"fallback"
	).expect()

	expectEqual(value, "fallback")
end

--————————————————————————————————————————————————————————————————————--

function tests.retry()
	local attempts = 0

	local value = promily.retry(function(attempt: number): string | promily.promise<string>
		attempts = attempt

		if attempt < 3 then
			local rejectedAttempt: promily.promise<string> = promily.reject("retry")

			return rejectedAttempt
		end

		return "success"
	end, {
		attempts = 3,
		delaySeconds = .001,
	}).expect()

	expectEqual(value, "success")
	expectEqual(attempts, 3)
end

--————————————————————————————————————————————————————————————————————--

function tests.fromEvent()
	local event = Instance.new("BindableEvent")

	task.defer(function()
		event:Fire("hello", 5)
	end)

	local arguments = promily.fromEvent(event.Event).expect()

	expectEqual(arguments[1], "hello")
	expectEqual(arguments[2], 5)

	event:Destroy()
end

--————————————————————————————————————————————————————————————————————--

function tests.fromAttribute()
	local folder = Instance.new("Folder")

	task.defer(function()
		folder:SetAttribute("ready", true)
	end)

	local promiseValue: promily.promise<boolean> = promily.fromAttribute(
		folder,
		"ready",
		{
			predicate = function(current: boolean): boolean
				return current == true
			end,
		}
	)

	local value = promiseValue.expect()

	expectEqual(value, true)

	folder:Destroy()
end

--————————————————————————————————————————————————————————————————————--

function tests.fromProperty()
	local part = Instance.new("Part")

	part.Transparency = 0

	task.defer(function()
		part.Transparency = 1
	end)

	local promiseValue: promily.promise<number> = promily.fromProperty(
		part,
		"Transparency",
		{
			predicate = function(current: number): boolean
				return current == 1
			end,
		}
	)

	local value = promiseValue.expect()

	expectEqual(value, 1)

	part:Destroy()
end

--————————————————————————————————————————————————————————————————————--

function tests.fromChild()
	local folder = Instance.new("Folder")

	task.defer(function()
		local child = Instance.new("Folder")

		child.Name = "Target"
		child.Parent = folder
	end)

	local child = promily.fromChild(folder, "Target", {
		className = "Folder",
		timeoutSeconds = 1,
	}).expect()

	expectEqual(child.Name, "Target")

	folder:Destroy()
end

--————————————————————————————————————————————————————————————————————--

function tests.wrap()
	local asyncDouble = promily.wrap(function(value: number): number
		return value * 2
	end)

	expectEqual(asyncDouble(6).expect(), 12)
end

--————————————————————————————————————————————————————————————————————--

function tests.toResult()
	local result = promily.reject("reason")
		.toResult()
		.expect()

	expectEqual(result.status, promily.status.rejected)
	expectEqual(result.reason, "reason")
end

--————————————————————————————————————————————————————————————————————--

return tests
