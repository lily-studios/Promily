--!strict

-- verifies Promily core behavior, cancellation, combinators, and Roblox adapters

local replicatedStorage = game:GetService("ReplicatedStorage")

local Promily = require(replicatedStorage:WaitForChild("Promily"))

--————————————————————————————————————————————————————————————————————--

local tests = {}

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
	local value = Promily.resolve(5)
		.andThen(function(current)
			return current * 2
		end)
		.expect()

	expectEqual(value, 10)
end

--————————————————————————————————————————————————————————————————————--

function tests.rejectionRecovery()
	local value = Promily.reject<number>("failure")
		.catch(function(reason)
			expectEqual(reason, "failure")
			return 12
		end)
		.expect()

	expectEqual(value, 12)
end

--————————————————————————————————————————————————————————————————————--

function tests.finallyPreservesValue()
	local cleanupCount = 0

	local value = Promily.resolve("done")
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
	local started = Promily.defer<boolean>()

	local promiseValue = Promily.new(function(_resolve, _reject, onCancel)
		onCancel(function(_reason)
			cleanupCount += 1
		end)

		started.resolve(true)
	end)

	started.promise.expect()
	expectTrue(promiseValue.cancel("test"))

	local settledStatus, reason = promiseValue.awaitStatus()

	expectEqual(settledStatus, Promily.status.cancelled)
	expectEqual(reason, "test")
	expectEqual(cleanupCount, 1)
end

--————————————————————————————————————————————————————————————————————--

function tests.cancellationSource()
	local source = Promily.createCancellationSource()
	local promiseValue = Promily.never(source.getToken())

	source.cancel("scope")

	local settledStatus, reason = promiseValue.awaitStatus()

	expectEqual(settledStatus, Promily.status.cancelled)
	expectEqual(reason, "scope")

	source.delete()
end

--————————————————————————————————————————————————————————————————————--

function tests.scopeCancellation()
	local scope = Promily.createScope()

	local promiseValue = scope.newPromise(function(_resolve, _reject, onCancel)
		local timer = task.delay(10, function()
		end)

		onCancel(function(_reason)
			task.cancel(timer)
		end)
	end)

	expectEqual(scope.getCount(), 1)

	scope.cancel("closed")

	local settledStatus, reason = promiseValue.awaitStatus()

	expectEqual(settledStatus, Promily.status.cancelled)
	expectEqual(reason, "closed")

	scope.delete()
end

--————————————————————————————————————————————————————————————————————--

function tests.all()
	local values = Promily.all({
		Promily.resolve(1),
		2,
		Promily.delay(.001, 3),
	}).expect()

	expectEqual(values[1], 1)
	expectEqual(values[2], 2)
	expectEqual(values[3], 3)
end

--————————————————————————————————————————————————————————————————————--

function tests.allSettled()
	local results = Promily.allSettled({
		Promily.resolve("yes"),
		Promily.reject("no"),
		Promily.cancelled("stop"),
	}).expect()

	expectEqual(results[1].status, Promily.status.resolved)
	expectEqual(results[2].status, Promily.status.rejected)
	expectEqual(results[3].status, Promily.status.cancelled)
end

--————————————————————————————————————————————————————————————————————--

function tests.any()
	local value = Promily.any({
		Promily.reject("one"),
		Promily.delay(.001, "two"),
	}).expect()

	expectEqual(value, "two")
end

--————————————————————————————————————————————————————————————————————--

function tests.some()
	local values = Promily.some({
		Promily.delay(.001, 1),
		Promily.resolve(2),
		Promily.reject("ignored"),
	}, 2).expect()

	expectEqual(#values, 2)
end

--————————————————————————————————————————————————————————————————————--

function tests.props()
	local values = Promily.props({
		first = Promily.resolve(10),
		second = 20,
	}).expect()

	expectEqual(values.first, 10)
	expectEqual(values.second, 20)
end

--————————————————————————————————————————————————————————————————————--

function tests.mapConcurrency()
	local active = 0
	local maximumActive = 0

	local results = Promily.map(
		{1, 2, 3, 4, 5},
		function(value)
			active += 1
			maximumActive = math.max(maximumActive, active)

			return Promily.delay(.001, value * 2)
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

	local results = Promily.sequence({
		function()
			order[#order + 1] = 1
			return Promily.delay(.001, "a")
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
	local total = Promily.reduce(
		{1, 2, 3, 4},
		function(accumulator, value)
			return accumulator + value
		end,
		0
	).expect()

	expectEqual(total, 10)
end

--————————————————————————————————————————————————————————————————————--

function tests.timeout()
	local settledStatus = Promily.never()
		.timeout(.001)
		.awaitStatus()

	expectEqual(settledStatus, Promily.status.rejected)
end

--————————————————————————————————————————————————————————————————————--

function tests.timeoutFallback()
	local value = Promily.timeoutOr(
		Promily.never(),
		.001,
		"fallback"
	).expect()

	expectEqual(value, "fallback")
end

--————————————————————————————————————————————————————————————————————--

function tests.retry()
	local attempts = 0

	local value = Promily.retry(function(attempt)
		attempts = attempt

		if attempt < 3 then
			return Promily.reject("retry")
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

	local arguments = Promily.fromEvent(event.Event).expect()

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

	local value = Promily.fromAttribute<boolean>(
		folder,
		"ready",
		{
			predicate = function(current)
				return current == true
			end,
		}
	).expect()

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

	local value = Promily.fromProperty<number>(
		part,
		"Transparency",
		{
			predicate = function(current)
				return current == 1
			end,
		}
	).expect()

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

	local child = Promily.fromChild(folder, "Target", {
		className = "Folder",
		timeoutSeconds = 1,
	}).expect()

	expectEqual(child.Name, "Target")

	folder:Destroy()
end

--————————————————————————————————————————————————————————————————————--

function tests.wrap()
	local asyncDouble = Promily.wrap(function(value: number)
		return value * 2
	end)

	expectEqual(asyncDouble(6).expect(), 12)
end

--————————————————————————————————————————————————————————————————————--

function tests.toResult()
	local result = Promily.reject("reason")
		.toResult()
		.expect()

	expectEqual(result.status, Promily.status.rejected)
	expectEqual(result.reason, "reason")
end

--————————————————————————————————————————————————————————————————————--

return tests
