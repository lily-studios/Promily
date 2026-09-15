--!strict

-- implements one-shot timing, timeout, and retry utilities

local module = {}

--————————————————————————————————————————————————————————————————————--

local random = Random.new()

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
local errors = require(core:WaitForChild("errors"))
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

--- Resolves after a non-negative delay with an optional value.
---@generic T
---@param seconds number Delay duration in seconds.
---@param value T? Optional resolved value.
---@return promiseModule.promise<T?> promiseValue Delayed Promise.
function module.delay<T>(seconds: number, value: T?): promiseModule.promise<T?>
	assert(seconds == seconds and seconds < math.huge and seconds >= 0, "Promily.delay() seconds must be finite and non-negative.")

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

--- Resolves after a non-negative delay without a payload.
---@param seconds number Delay duration in seconds.
---@return promiseModule.promise<nil> promiseValue Sleep Promise.
function module.sleep(seconds: number): promiseModule.promise<nil>
	return module.delay(seconds, nil)
end

--————————————————————————————————————————————————————————————————————--

--- Creates a Promise that rejects after the requested delay.
---@generic T
---@param seconds number Non-negative delay in seconds.
---@param reason any Rejection reason delivered when the timer expires.
---@return promise<T> promiseValue Rejecting timer Promise.
function module.rejectAfter<T>(seconds: number, reason: any): promiseModule.promise<T>
	assert(
		seconds == seconds and seconds < math.huge and seconds >= 0,
		"Promily.rejectAfter() seconds must be finite and non-negative."
	)

	return promiseModule.new(function(_resolve, reject, onCancel)
		local timerThread: thread?

		timerThread = task.delay(seconds, function()
			timerThread = nil
			reject(reason)
		end)

		onCancel(function(_reason)
			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Applies a relative timeout to a source Promise without cancelling the source.
---@generic T
---@param source T | promiseModule.promise<T> Source value or Promise.
---@param seconds number Timeout duration in seconds.
---@param options promiseModule.timeoutOptions? Optional timeout reason or fallback.
---@return promiseModule.promise<T> promiseValue Timeout-bound consumer Promise.
function module.timeout<T>(
	source: T | promiseModule.promise<T>,
	seconds: number,
	options: promiseModule.timeoutOptions?
): promiseModule.promise<T>
	return promiseModule.resolve(source).timeout(seconds, options)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves with a fallback when a source does not settle before the timeout.
---@generic T
---@generic R
---@param source T | promiseModule.promise<T> Source value or Promise.
---@param seconds number Timeout duration in seconds.
---@param fallback R | promiseModule.promise<R> Timeout fallback value or Promise.
---@return promiseModule.promise<T | R> promiseValue Source or fallback result.
function module.timeoutOr<T, R>(
	source: T | promiseModule.promise<T>,
	seconds: number,
	fallback: R | promiseModule.promise<R>
): promiseModule.promise<T | R>
	local sourcePromise = promiseModule.resolve(source)
	local timeoutPromise = sourcePromise.timeoutOr(seconds, fallback)

	-- Luau cannot currently preserve the transformed Promise generic through the
	-- recursive promiseBase boundary. The runtime value is still a Promily Promise;
	-- restore the public T | R view only at this module boundary.
	return timeoutPromise :: any
end

--————————————————————————————————————————————————————————————————————--

--- Retries a lazy operation using the requested attempt, delay, backoff, and jitter policy.
---@generic T
---@param callback fun(attempt: number): T | promiseModule.promise<T> Attempt callback.
---@param options retryOptions? Optional retry policy.
---@return promiseModule.promise<T> promiseValue Retried operation.
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

	assert(
		attempts == attempts and attempts < math.huge and attempts >= 1 and attempts % 1 == 0,
		"Promily.retry() attempts must be a finite positive integer."
	)
	assert(backoff == backoff and backoff < math.huge and backoff >= 0, "Promily.retry() backoff must be finite and non-negative.")
	assert(
		delaySeconds == delaySeconds and delaySeconds < math.huge and delaySeconds >= 0,
		"Promily.retry() delaySeconds must be finite and non-negative."
	)
	assert(jitter == jitter and jitter >= 0 and jitter <= 1, "Promily.retry() jitter must be between 0 and 1.")

	if maximumDelay ~= nil then
		assert(maximumDelay == maximumDelay and maximumDelay < math.huge and maximumDelay >= 0, "Promily.retry() maximumDelay must be finite and non-negative.")
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
					onRejected(errors.cancelledAttempt(reason))
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
