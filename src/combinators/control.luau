--!strict

-- implements one-shot timing, timeout, and retry utilities

local module = {}

--————————————————————————————————————————————————————————————————————--

local random = Random.new()

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type retryOptions = {
	attempts: number?,
	backoff: number?,
	delaySeconds: number?,
	jitter: number?,
	maximumDelay: number?,
	shouldRetry: ((reason: any, attempt: number) -> boolean)?,
}

--————————————————————————————————————————————————————————————————————--

function module.delay<T>(seconds: number, value: T?): promiseModule.promise<T?>
	assert(seconds >= 0, "Promily.delay() seconds must be non-negative.")

	return promiseModule.new(function(resolve, _reject, onCancel)
		local timerThread: thread?

		timerThread = task.delay(seconds, function()
			timerThread = nil
			resolve(value)
		end)

		onCancel(function(_reason)
			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.sleep(seconds: number): promiseModule.promise<nil>
	return module.delay(seconds, nil)
end

--————————————————————————————————————————————————————————————————————--

function module.timeout<T>(
	source: T | promiseModule.promise<T>,
	seconds: number,
	options: promiseModule.timeoutOptions?
): promiseModule.promise<T>
	return promiseModule.resolve(source).timeout(seconds, options)
end

--————————————————————————————————————————————————————————————————————--

function module.timeoutOr<T, R>(
	source: T | promiseModule.promise<T>,
	seconds: number,
	fallback: R | promiseModule.promise<R>
): promiseModule.promise<T | R>
	return promiseModule.resolve(source).timeoutOr(seconds, fallback)
end

--————————————————————————————————————————————————————————————————————--

function module.retry<T>(
	callback: (attempt: number) -> (T | promiseModule.promise<T>),
	options: retryOptions?
): promiseModule.promise<T>
	local attempts = 3
	local backoff = 1
	local delaySeconds = 0
	local jitter = 0
	local maximumDelay: number? = nil
	local shouldRetry: ((reason: any, attempt: number) -> boolean)? = nil

	if options then
		if options.attempts ~= nil then
			attempts = options.attempts
		end

		if options.backoff ~= nil then
			backoff = options.backoff
		end

		if options.delaySeconds ~= nil then
			delaySeconds = options.delaySeconds
		end

		if options.jitter ~= nil then
			jitter = options.jitter
		end

		maximumDelay = options.maximumDelay
		shouldRetry = options.shouldRetry
	end

	assert(attempts >= 1, "Promily.retry() attempts must be at least 1.")
	assert(backoff >= 0, "Promily.retry() backoff must be non-negative.")
	assert(delaySeconds >= 0, "Promily.retry() delaySeconds must be non-negative.")
	assert(jitter >= 0 and jitter <= 1, "Promily.retry() jitter must be between 0 and 1.")

	if maximumDelay ~= nil then
		assert(maximumDelay >= 0, "Promily.retry() maximumDelay must be non-negative.")
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local activeObserver: promiseModule.observer<T>?
		local activePromise: promiseModule.promise<T>?
		local attempt = 0
		local isStopped = false
		local timerThread: thread?

		local runAttempt: () -> ()

		local function disconnectActiveObserver()
			local observerValue = activeObserver
			activeObserver = nil

			if not observerValue then return end

			observerValue.disconnect()
		end

		local function stop(reason: any?)
			if isStopped then return end

			isStopped = true
			disconnectActiveObserver()

			local promiseValue = activePromise
			activePromise = nil

			if promiseValue then
				promiseValue.cancel(reason)
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function getNextDelay(): number
			local retryIndex = math.max(attempt - 1, 0)
			local nextDelay = delaySeconds * (backoff ^ retryIndex)

			if maximumDelay ~= nil then
				nextDelay = math.min(nextDelay, maximumDelay)
			end

			if jitter == 0 then
				return nextDelay
			end

			local jitterScale = random:NextNumber(1 - jitter, 1 + jitter)

			return math.max(nextDelay * jitterScale, 0)
		end

		local function scheduleNext()
			local nextDelay = getNextDelay()

			if nextDelay == 0 then
				task.defer(runAttempt)
				return
			end

			timerThread = task.delay(nextDelay, function()
				timerThread = nil
				runAttempt()
			end)
		end

		local function onRejected(reason: any)
			if isStopped then return end

			disconnectActiveObserver()

			local canRetry = attempt < attempts

			if canRetry and shouldRetry then
				local success, retryDecision = pcall(shouldRetry, reason, attempt)

				if not success then
					isStopped = true
					reject(retryDecision)
					return
				end

				canRetry = retryDecision
			end

			if not canRetry then
				isStopped = true
				reject(reason)
				return
			end

			scheduleNext()
		end

		runAttempt = function()
			if isStopped then return end

			attempt += 1

			local attemptPromise = promiseModule.try(function()
				return callback(attempt)
			end)

			activePromise = attemptPromise

			activeObserver = attemptPromise.observe(
				function(value: T)
					if isStopped then return end

					isStopped = true
					disconnectActiveObserver()
					activePromise = nil
					resolve(value)
				end,
				onRejected,
				function(reason: any?)
					onRejected({
						kind = "CancelledAttempt",
						reason = reason,
					})
				end
			)
		end

		onCancel(function(reason)
			stop(reason)
		end)
		runAttempt()
	end)
end

--————————————————————————————————————————————————————————————————————--

return module
