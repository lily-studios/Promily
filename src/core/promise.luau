--!strict

-- implements the Promily promise state machine, chaining, inspection, and lifecycle

local module = {}

--————————————————————————————————————————————————————————————————————--

local status = table.freeze({
	cancelled = "Cancelled",
	pending = "Pending",
	rejected = "Rejected",
	resolved = "Resolved",
})

local nextPromiseId = 0
local promiseContexts = setmetatable({}, {__mode = "k"})

local unhandledRejectionHandler: (promiseValue: any, reason: any) -> () = function(promiseValue, reason)
	local label = promiseValue.getLabel()
	local suffix = ""

	if label then
		suffix = ` ({label})`
	end

	warn(`[Promily] Unhandled promise rejection{suffix}:`, reason)
end

--————————————————————————————————————————————————————————————————————--

export type promiseStatus =
	"Cancelled"
	| "Pending"
	| "Rejected"
	| "Resolved"

export type cancellationToken = {
	getReason: () -> any?,
	isCancelled: () -> boolean,
	onCancelled: (callback: (reason: any?) -> ()) -> {
		connected: boolean,
		disconnect: () -> boolean,
	},
	throwIfCancelled: (message: string?) -> (),
}

export type connection = {
	connected: boolean,
	disconnect: () -> boolean,
}

export type result<T> = {
	id: number,
	isSettled: boolean,
	label: string?,
	reason: any?,
	status: promiseStatus,
	value: T?,
}

export type deferred<T> = {
	cancel: (reason: any?) -> boolean,
	promise: promise<T>,
	reject: (reason: any) -> boolean,
	resolve: (value: T | promise<T>) -> boolean,
}

export type observer<T> = {
	connected: boolean,
	disconnect: () -> boolean,
}

export type promise<T> = {
	andThen: <R>(
		onResolved: ((value: T) -> (R | promise<R>))?,
		onRejected: ((reason: any) -> (R | promise<R>))?
	) -> promise<R>,
	andThenReturn: <R>(value: R | promise<R>) -> promise<R>,
	await: () -> (boolean, any?),
	awaitResult: () -> result<T>,
	awaitStatus: () -> (promiseStatus, any?),
	cancel: (reason: any?) -> boolean,
	catch: <R>(onRejected: (reason: any) -> (R | promise<R>)) -> promise<T | R>,
	catchReturn: <R>(value: R | promise<R>) -> promise<T | R>,
	delay: (seconds: number) -> promise<T>,
	expect: (message: string?) -> T,
	finally: (callback: () -> any) -> promise<T>,
	getId: () -> number,
	getLabel: () -> string?,
	getStatus: () -> promiseStatus,
	inspect: () -> result<T>,
	isCancelled: () -> boolean,
	isPending: () -> boolean,
	isRejected: () -> boolean,
	isResolved: () -> boolean,
	isSettled: () -> boolean,
	label: (name: string) -> promise<T>,
	observe: (
		onResolved: ((value: T) -> ())?,
		onRejected: ((reason: any) -> ())?,
		onCancelled: ((reason: any?) -> ())?
	) -> observer<T>,
	observeSettled: (callback: (resultValue: result<T>) -> ()) -> observer<T>,
	tap: (callback: (value: T) -> any) -> promise<T>,
	tapError: (callback: (reason: any) -> any) -> promise<T>,
	timeout: (seconds: number, options: timeoutOptions?) -> promise<T>,
	timeoutOr: <R>(seconds: number, fallback: R | promise<R>) -> promise<T | R>,
	toResult: () -> promise<result<T>>,
}

export type timeoutOptions = {
	fallback: any?,
	hasFallback: boolean?,
	reason: any?,
}

type observerRecord = {
	connected: boolean,
	connectionValue: observer<any>?,
	dispatched: boolean,
	handlesRejection: boolean,
	onCancelled: ((reason: any?) -> ())?,
	onRejected: ((reason: any) -> ())?,
	onResolved: ((value: any) -> ())?,
}

type promiseContext = {
	cancelHandlers: {(reason: any?) -> ()},
	id: number,
	isFlushing: boolean,
	isHandled: boolean,
	label: string?,
	observers: {observerRecord},
	promiseValue: any?,
	reason: any?,
	status: promiseStatus,
	tokenConnection: {
		connected: boolean,
		disconnect: () -> boolean,
	}?,
	value: any?,
}

--————————————————————————————————————————————————————————————————————--

local function getContext<T>(promiseValue: promise<T>): promiseContext
	local context = promiseContexts[promiseValue]
	assert(context, "Value is not a Promily promise.")

	return context
end

--————————————————————————————————————————————————————————————————————--

local function isPromise(value: any): boolean
	if type(value) ~= "table" then return false end

	return promiseContexts[value] ~= nil
end

--————————————————————————————————————————————————————————————————————--

local function disconnectObserver(observerValue: observerRecord): boolean
	if not observerValue.connected then return false end

	observerValue.connected = false

	local connectionValue = observerValue.connectionValue

	if connectionValue then
		connectionValue.connected = false
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

local function reportUnhandled(context: promiseContext)
	if context.status ~= status.rejected then return end
	if context.isHandled then return end

	local promiseValue = context.promiseValue
	if not promiseValue then return end

	local success, failure = pcall(
		unhandledRejectionHandler,
		promiseValue,
		context.reason
	)

	if success then return end

	warn("[Promily] Unhandled rejection handler failed:", failure)
end

--————————————————————————————————————————————————————————————————————--

local function scheduleUnhandledCheck(context: promiseContext)
	task.defer(function()
		reportUnhandled(context)
	end)
end

--————————————————————————————————————————————————————————————————————--

local function dispatchObserver(context: promiseContext, observerValue: observerRecord)
	if not observerValue.connected then return end
	if observerValue.dispatched then return end

	observerValue.dispatched = true
	observerValue.connected = false

	local connectionValue = observerValue.connectionValue

	if connectionValue then
		connectionValue.connected = false
	end

	if context.status == status.resolved then
		local callback = observerValue.onResolved
		if not callback then return end

		callback(context.value)
		return
	end

	if context.status == status.rejected then
		local callback = observerValue.onRejected
		if not callback then return end

		callback(context.reason)
		return
	end

	if context.status == status.cancelled then
		local callback = observerValue.onCancelled
		if not callback then return end

		callback(context.reason)
	end
end

--————————————————————————————————————————————————————————————————————--

local function flushObservers(context: promiseContext)
	if context.isFlushing then return end
	if context.status == status.pending then return end

	context.isFlushing = true

	local currentObservers = context.observers
	context.observers = {}

	for _, observerValue in currentObservers do
		dispatchObserver(context, observerValue)
	end

	table.clear(currentObservers)
	context.isFlushing = false

	if #context.observers == 0 then return end

	task.defer(flushObservers, context)
end

--————————————————————————————————————————————————————————————————————--

local function scheduleFlush(context: promiseContext)
	if context.isFlushing then return end

	task.defer(flushObservers, context)
end

--————————————————————————————————————————————————————————————————————--

local function runCancelHandlers(context: promiseContext)
	local handlers = context.cancelHandlers
	context.cancelHandlers = {}

	for index = #handlers, 1, -1 do
		local callback = handlers[index]

		local success, failure = pcall(callback, context.reason)

		if success then continue end

		warn("[Promily] Cancellation cleanup failed:", failure)
	end

	table.clear(handlers)
end

--————————————————————————————————————————————————————————————————————--

local function settle(
	context: promiseContext,
	nextStatus: promiseStatus,
	value: any?,
	reason: any?
): boolean
	if context.status ~= status.pending then return false end

	context.status = nextStatus
	context.value = value
	context.reason = reason

	local tokenConnection = context.tokenConnection
	context.tokenConnection = nil

	if tokenConnection then
		tokenConnection.disconnect()
	end

	if nextStatus == status.cancelled then
		runCancelHandlers(context)
	end

	if nextStatus ~= status.cancelled then
		table.clear(context.cancelHandlers)
	end

	scheduleFlush(context)

	if nextStatus == status.rejected then
		scheduleUnhandledCheck(context)
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

local function observeInternal(
	context: promiseContext,
	onResolved: ((value: any) -> ())?,
	onRejected: ((reason: any) -> ())?,
	onCancelled: ((reason: any?) -> ())?,
	handlesRejection: boolean?
): observer<any>
	local shouldHandleRejection = handlesRejection

	if shouldHandleRejection == nil then
		shouldHandleRejection = onRejected ~= nil
	end

	if shouldHandleRejection then
		context.isHandled = true
	end

	local observerValue: observerRecord = {
		connected = true,
		connectionValue = nil,
		dispatched = false,
		handlesRejection = shouldHandleRejection,
		onCancelled = onCancelled,
		onRejected = onRejected,
		onResolved = onResolved,
	}

	local connectionValue: observer<any> = {
		connected = true,

		disconnect = function(): boolean
			return disconnectObserver(observerValue)
		end,
	}

	observerValue.connectionValue = connectionValue
	context.observers[#context.observers + 1] = observerValue

	if context.status ~= status.pending then
		scheduleFlush(context)
	end

	return connectionValue
end

--————————————————————————————————————————————————————————————————————--

local function resolveContext(context: promiseContext, value: any): boolean
	if context.status ~= status.pending then return false end

	local promiseValue = context.promiseValue

	if value == promiseValue then
		return settle(
			context,
			status.rejected,
			nil,
			"Promily promise cannot resolve with itself."
		)
	end

	if not isPromise(value) then
		return settle(context, status.resolved, value, nil)
	end

	local sourceContext = promiseContexts[value]
	assert(sourceContext, "Promily source promise context is missing.")

	local connectionValue: observer<any>?

	connectionValue = observeInternal(
		sourceContext,
		function(resolvedValue)
			if connectionValue then
				connectionValue.disconnect()
			end

			resolveContext(context, resolvedValue)
		end,
		function(rejectionReason)
			if connectionValue then
				connectionValue.disconnect()
			end

			settle(context, status.rejected, nil, rejectionReason)
		end,
		function(cancelReason)
			if connectionValue then
				connectionValue.disconnect()
			end

			settle(context, status.cancelled, nil, cancelReason)
		end
	)

	context.cancelHandlers[#context.cancelHandlers + 1] = function(_reason)
		if not connectionValue then return end

		connectionValue.disconnect()
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

local function createPending<T>(token: cancellationToken?): (promise<T>, deferred<T>)
	nextPromiseId += 1

	local context: promiseContext = {
		cancelHandlers = {},
		id = nextPromiseId,
		isFlushing = false,
		isHandled = false,
		label = nil,
		observers = {},
		promiseValue = nil,
		reason = nil,
		status = status.pending,
		tokenConnection = nil,
		value = nil,
	}

	local promiseValue: promise<T>
	local deferredValue: deferred<T>

	local function resolve(value: T | promise<T>): boolean
		return resolveContext(context, value)
	end

	local function reject(reason: any): boolean
		return settle(context, status.rejected, nil, reason)
	end

	local function cancel(reason: any?): boolean
		return settle(context, status.cancelled, nil, reason)
	end

	local function observe(
		onResolved: ((value: T) -> ())?,
		onRejected: ((reason: any) -> ())?,
		onCancelled: ((reason: any?) -> ())?
	): observer<T>
		return observeInternal(
			context,
			onResolved :: ((value: any) -> ())?,
			onRejected,
			onCancelled
		) :: observer<T>
	end

	local function observeSettled(
		callback: (resultValue: result<T>) -> ()
	): observer<T>
		return observeInternal(
			context,
			function()
				callback({
					id = context.id,
					isSettled = true,
					label = context.label,
					reason = nil,
					status = status.resolved,
					value = context.value,
				})
			end,
			function()
				callback({
					id = context.id,
					isSettled = true,
					label = context.label,
					reason = context.reason,
					status = status.rejected,
					value = nil,
				})
			end,
			function()
				callback({
					id = context.id,
					isSettled = true,
					label = context.label,
					reason = context.reason,
					status = status.cancelled,
					value = nil,
				})
			end,
			false
		) :: observer<T>
	end

--————————————————————————————————————————————————————————————————————--

	local function andThen<R>(
		onResolved: ((value: T) -> (R | promise<R>))?,
		onRejected: ((reason: any) -> (R | promise<R>))?
	): promise<R>
		local childPromise, childDeferred = createPending<R>()
		local parentObserver: observer<T>?

		local function resolveChildWithCallback(callback: (value: any) -> any, input: any)
			local success, output = pcall(callback, input)

			if not success then
				childDeferred.reject(output)
				return
			end

			childDeferred.resolve(output)
		end

		parentObserver = observe(
			function(value: T)
				if not onResolved then
					childDeferred.resolve(value :: any)
					return
				end

				resolveChildWithCallback(onResolved, value)
			end,
			function(reasonValue: any)
				if not onRejected then
					childDeferred.reject(reasonValue)
					return
				end

				resolveChildWithCallback(onRejected, reasonValue)
			end,
			function(cancelReason: any?)
				childDeferred.cancel(cancelReason)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if not parentObserver then return end

			parentObserver.disconnect()
		end

		return childPromise
	end

	local function catch<R>(onRejected: (reason: any) -> (R | promise<R>)): promise<T | R>
		return andThen(nil, onRejected) :: promise<T | R>
	end

	local function finally(callback: () -> any): promise<T>
		local childPromise, childDeferred = createPending<T>()
		local cleanupObserver: observer<any>?
		local parentObserver: observer<T>?

		local function runFinally(nextStatus: promiseStatus, settledValue: any?)
			local success, callbackResult = pcall(callback)

			if not success then
				childDeferred.reject(callbackResult)
				return
			end

			local cleanupPromise = module.resolve(callbackResult)

			cleanupObserver = cleanupPromise.observe(
				function()
					cleanupObserver = nil

					if nextStatus == status.resolved then
						childDeferred.resolve(settledValue)
						return
					end

					if nextStatus == status.rejected then
						childDeferred.reject(settledValue)
						return
					end

					childDeferred.cancel(settledValue)
				end,
				function(reasonValue)
					cleanupObserver = nil
					childDeferred.reject(reasonValue)
				end,
				function(reasonValue)
					cleanupObserver = nil
					childDeferred.cancel(reasonValue)
				end
			)
		end

		parentObserver = observe(
			function(value: T)
				runFinally(status.resolved, value)
			end,
			function(reasonValue: any)
				runFinally(status.rejected, reasonValue)
			end,
			function(reasonValue: any?)
				runFinally(status.cancelled, reasonValue)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if parentObserver then
				parentObserver.disconnect()
			end

			if cleanupObserver then
				cleanupObserver.disconnect()
				cleanupObserver = nil
			end
		end

		return childPromise
	end

--————————————————————————————————————————————————————————————————————--

	local function tap(callback: (value: T) -> any): promise<T>
		return andThen(function(value: T)
			local success, callbackResult = pcall(callback, value)

			if not success then
				return module.reject(callbackResult) :: any
			end

			return module.resolve(callbackResult).andThen(function()
				return value
			end)
		end) :: promise<T>
	end

	local function tapError(callback: (reason: any) -> any): promise<T>
		return catch(function(reasonValue: any)
			local success, callbackResult = pcall(callback, reasonValue)

			if not success then
				return module.reject(callbackResult)
			end

			return module.resolve(callbackResult).andThen(function()
				return module.reject(reasonValue)
			end)
		end) :: promise<T>
	end

	local function andThenReturn<R>(value: R | promise<R>): promise<R>
		return andThen(function()
			return value
		end)
	end

	local function catchReturn<R>(value: R | promise<R>): promise<T | R>
		return catch(function()
			return value
		end)
	end

	local function getStatus(): promiseStatus
		return context.status
	end

	local function isPending(): boolean
		return context.status == status.pending
	end

	local function isResolved(): boolean
		return context.status == status.resolved
	end

	local function isRejected(): boolean
		return context.status == status.rejected
	end

	local function isCancelled(): boolean
		return context.status == status.cancelled
	end

	local function isSettled(): boolean
		return context.status ~= status.pending
	end

	local function inspect(): result<T>
		return {
			id = context.id,
			isSettled = context.status ~= status.pending,
			label = context.label,
			reason = context.reason,
			status = context.status,
			value = context.value,
		}
	end

	local function awaitStatus(): (promiseStatus, any?)
		if context.status == status.resolved then
			return context.status, context.value
		end

		if context.status == status.rejected
			or context.status == status.cancelled
		then
			return context.status, context.reason
		end

		local thread = coroutine.running()
		assert(thread, "Promily.awaitStatus() must be called from a yieldable thread.")

		local observerValue: observer<T>?

		observerValue = observe(
			function(value: T)
				if observerValue then
					observerValue.disconnect()
				end

				task.spawn(thread, status.resolved, value)
			end,
			function(reasonValue: any)
				if observerValue then
					observerValue.disconnect()
				end

				task.spawn(thread, status.rejected, reasonValue)
			end,
			function(reasonValue: any?)
				if observerValue then
					observerValue.disconnect()
				end

				task.spawn(thread, status.cancelled, reasonValue)
			end
		)

		return coroutine.yield()
	end

	local function await(): (boolean, any?)
		local settledStatus, settledValue = awaitStatus()

		return settledStatus == status.resolved, settledValue
	end

	local function awaitResult(): result<T>
		awaitStatus()

		return inspect()
	end

	local function expect(message: string?): T
		local settledStatus, settledValue = awaitStatus()

		if settledStatus == status.resolved then
			return settledValue :: T
		end

		local prefix = message

		if prefix == nil then
			prefix = "Promily promise did not resolve."
		end

		error(`{prefix} Status: {settledStatus}. Reason: {tostring(settledValue)}`, 2)
	end

	local function label(name: string): promise<T>
		assert(name ~= "", "Promily promise label cannot be empty.")

		context.label = name

		return promiseValue
	end

	local function getLabel(): string?
		return context.label
	end

	local function getId(): number
		return context.id
	end

	local function delay(seconds: number): promise<T>
		assert(seconds >= 0, "Promily delay must be non-negative.")

		local childPromise, childDeferred = createPending<T>()
		local timerThread: thread?

		local function scheduleSettlement(nextStatus: promiseStatus, settledValue: any?)
			timerThread = task.delay(seconds, function()
				timerThread = nil

				if nextStatus == status.resolved then
					childDeferred.resolve(settledValue)
					return
				end

				if nextStatus == status.rejected then
					childDeferred.reject(settledValue)
					return
				end

				childDeferred.cancel(settledValue)
			end)
		end

		local parentObserver = observe(
			function(value: T)
				scheduleSettlement(status.resolved, value)
			end,
			function(reasonValue: any)
				scheduleSettlement(status.rejected, reasonValue)
			end,
			function(reasonValue: any?)
				scheduleSettlement(status.cancelled, reasonValue)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			parentObserver.disconnect()

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		return childPromise
	end

	local function timeout(seconds: number, options: timeoutOptions?): promise<T>
		assert(seconds >= 0, "Promily timeout must be non-negative.")

		local childPromise, childDeferred = createPending<T>()
		local hasFallback = false
		local fallback: any? = nil
		local timeoutReason: any = `Promily promise timed out after {seconds} seconds.`

		if options then
			hasFallback = options.hasFallback == true
			fallback = options.fallback

			if options.reason ~= nil then
				timeoutReason = options.reason
			end
		end

		local settled = false
		local parentObserver: observer<T>?

		local timerThread = task.delay(seconds, function()
			if settled then return end

			settled = true

			if parentObserver then
				parentObserver.disconnect()
			end

			if hasFallback then
				childDeferred.resolve(fallback)
				return
			end

			childDeferred.reject(timeoutReason)
		end)

		parentObserver = observe(
			function(value: T)
				if settled then return end

				settled = true
				task.cancel(timerThread)
				childDeferred.resolve(value)
			end,
			function(reasonValue: any)
				if settled then return end

				settled = true
				task.cancel(timerThread)
				childDeferred.reject(reasonValue)
			end,
			function(reasonValue: any?)
				if settled then return end

				settled = true
				task.cancel(timerThread)
				childDeferred.cancel(reasonValue)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if settled then return end

			settled = true
			task.cancel(timerThread)

			if parentObserver then
				parentObserver.disconnect()
			end
		end

		return childPromise
	end

	local function timeoutOr<R>(seconds: number, fallback: R | promise<R>): promise<T | R>
		return timeout(seconds, {
			fallback = fallback,
			hasFallback = true,
		}) :: promise<T | R>
	end

	local function toResult(): promise<result<T>>
		local childPromise, childDeferred = createPending<result<T>>()
		local sourceObserver: observer<T>?

		sourceObserver = observe(
			function()
				sourceObserver = nil
				childDeferred.resolve(inspect())
			end,
			function()
				sourceObserver = nil
				childDeferred.resolve(inspect())
			end,
			function()
				sourceObserver = nil
				childDeferred.resolve(inspect())
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if not sourceObserver then return end

			sourceObserver.disconnect()
			sourceObserver = nil
		end

		return childPromise
	end

	promiseValue = {
		andThen = andThen,
		andThenReturn = andThenReturn,
		await = await,
		awaitResult = awaitResult,
		awaitStatus = awaitStatus,
		cancel = cancel,
		catch = catch,
		catchReturn = catchReturn,
		delay = delay,
		expect = expect,
		finally = finally,
		getId = getId,
		getLabel = getLabel,
		getStatus = getStatus,
		inspect = inspect,
		isCancelled = isCancelled,
		isPending = isPending,
		isRejected = isRejected,
		isResolved = isResolved,
		isSettled = isSettled,
		label = label,
		observe = observe,
		observeSettled = observeSettled,
		tap = tap,
		tapError = tapError,
		timeout = timeout,
		timeoutOr = timeoutOr,
		toResult = toResult,
	}

	context.promiseValue = promiseValue
	promiseContexts[promiseValue] = context

	deferredValue = {
		cancel = cancel,
		promise = promiseValue,
		reject = reject,
		resolve = resolve,
	}

	if token and token.isCancelled() then
		cancel(token.getReason())
	end

	if token and not token.isCancelled() then
		context.tokenConnection = token.onCancelled(function(reasonValue)
			cancel(reasonValue)
		end)
	end

	return promiseValue, deferredValue
end

--————————————————————————————————————————————————————————————————————--

function module.new<T>(
	executor: (
		resolve: (value: T | promise<T>) -> (),
		reject: (reason: any) -> (),
		onCancel: (callback: (reason: any?) -> ()) -> boolean
	) -> (),
	token: cancellationToken?
): promise<T>
	local promiseValue, deferredValue = createPending<T>(token)
	local context = getContext(promiseValue)

	task.spawn(function()
		if context.status ~= status.pending then return end

		local function onCancel(callback: (reason: any?) -> ()): boolean
			if context.status == status.cancelled then
				task.defer(callback, context.reason)
				return false
			end

			if context.status ~= status.pending then return false end

			context.cancelHandlers[#context.cancelHandlers + 1] = callback

			return true
		end

		local success, failure = pcall(
			executor,
			function(value: T | promise<T>)
				deferredValue.resolve(value)
			end,
			function(reason: any)
				deferredValue.reject(reason)
			end,
			onCancel
		)

		if success then return end

		deferredValue.reject(failure)
	end)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

function module.defer<T>(token: cancellationToken?): deferred<T>
	local _, deferredValue = createPending<T>(token)

	return deferredValue
end

--————————————————————————————————————————————————————————————————————--

function module.resolve<T>(value: T | promise<T>): promise<T>
	if isPromise(value) then
		return value :: promise<T>
	end

	local promiseValue, deferredValue = createPending<T>()
	deferredValue.resolve(value)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

function module.reject<T>(reason: any): promise<T>
	local promiseValue, deferredValue = createPending<T>()
	deferredValue.reject(reason)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

function module.cancelled<T>(reason: any?): promise<T>
	local promiseValue, deferredValue = createPending<T>()
	deferredValue.cancel(reason)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

function module.try<T>(
	callback: () -> (T | promise<T>),
	token: cancellationToken?
): promise<T>
	return module.new(function(resolve, reject)
		local success, output = pcall(callback)

		if not success then
			reject(output)
			return
		end

		resolve(output)
	end, token)
end

--————————————————————————————————————————————————————————————————————--

function module.wrap(
	callback: (...any) -> any
): (...any) -> promise<any>
	return function(...: any): promise<any>
		local arguments = table.pack(...)

		return module.try(function()
			return callback(table.unpack(arguments, 1, arguments.n))
		end)
	end
end

--————————————————————————————————————————————————————————————————————--

function module.is(value: any): boolean
	return isPromise(value)
end

--————————————————————————————————————————————————————————————————————--

function module.getStatusTable()
	return status
end

--————————————————————————————————————————————————————————————————————--

function module.setUnhandledRejectionHandler(
	callback: (promiseValue: any, reason: any) -> ()
)
	unhandledRejectionHandler = callback
end

--————————————————————————————————————————————————————————————————————--

return module
