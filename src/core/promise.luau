--!strict

-- implements the Promily promise state machine, chaining, inspection, and lifecycle

local module = {}

--————————————————————————————————————————————————————————————————————--

local nextPromiseId = 0
local lifetimeCreated = 0
local lifetimeCancelled = 0
local lifetimeRejected = 0
local lifetimeResolved = 0

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

type statusValues = {
	cancelled: promiseStatus,
	pending: promiseStatus,
	rejected: promiseStatus,
	resolved: promiseStatus,
}

local status: statusValues = {
	cancelled = "Cancelled",
	pending = "Pending",
	rejected = "Rejected",
	resolved = "Resolved",
}

table.freeze(status)

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
	createdAt: number,
	id: number,
	isSettled: boolean,
	label: string?,
	pendingFor: number,
	reason: any?,
	settledAt: number?,
	status: promiseStatus,
	value: T?,
}

export type diagnosticsSnapshot = result<any>

export type diagnosticsStats = {
	created: number,
	liveCancelled: number,
	livePending: number,
	liveRejected: number,
	liveResolved: number,
	liveTotal: number,
	totalCancelled: number,
	totalRejected: number,
	totalResolved: number,
}

export type observer<T> = {
	connected: boolean,
	disconnect: () -> boolean,
}

export type timeoutOptions = {
	fallback: any?,
	hasFallback: boolean?,
	reason: any?,
}

-- Luau currently rejects a recursive generic alias when one instantiation directly
-- contains another instantiation such as promise<T> -> promise<R>. Transformed
-- chains therefore expose the non-generic promiseBase surface, while operations
-- that preserve T retain the full promise<T> type.
export type promiseBase = {
	andThen: (onResolved: ((value: any) -> any)?, onRejected: ((reason: any) -> any)?) -> promiseBase,
	andThenReturn: (value: any) -> promiseBase,
	await: () -> (boolean, any?),
	awaitResult: () -> result<any>,
	awaitStatus: () -> (promiseStatus, any?),
	cancel: (reason: any?) -> boolean,
	catch: (onRejected: (reason: any) -> any) -> promiseBase,
	catchCancel: (onCancelled: (reason: any?) -> any) -> promiseBase,
	catchCancelReturn: (value: any) -> promiseBase,
	catchReturn: (value: any) -> promiseBase,
	deadline: (deadlineTime: number, reason: any?) -> promiseBase,
	delay: (seconds: number) -> promiseBase,
	expect: (message: string?) -> any,
	finally: (callback: () -> any) -> promiseBase,
	fork: () -> promiseBase,
	getId: () -> number,
	getLabel: () -> string?,
	getStatus: () -> promiseStatus,
	inspect: () -> result<any>,
	isCancelled: () -> boolean,
	isPending: () -> boolean,
	isRejected: () -> boolean,
	isResolved: () -> boolean,
	isSettled: () -> boolean,
	label: (name: string) -> promiseBase,
	onCancel: (callback: (reason: any?) -> ()) -> connection,
	observe: (
		onResolved: ((value: any) -> ())?,
		onRejected: ((reason: any) -> ())?,
		onCancelled: ((reason: any?) -> ())?
	) -> observer<any>,
	observeSettled: (callback: (resultValue: result<any>) -> ()) -> observer<any>,
	tap: (callback: (value: any) -> any) -> promiseBase,
	tapCancel: (callback: (reason: any?) -> any) -> promiseBase,
	tapError: (callback: (reason: any) -> any) -> promiseBase,
	tapSettled: (callback: (resultValue: result<any>) -> any) -> promiseBase,
	timeout: (seconds: number, options: timeoutOptions?) -> promiseBase,
	timeoutOr: (seconds: number, fallback: any) -> promiseBase,
	toResult: () -> promiseBase,
	withCancellation: (token: cancellationToken) -> promiseBase,
}

export type promise<T> = {
	andThen: <R>(
		onResolved: ((value: T) -> (R | promiseBase))?,
		onRejected: ((reason: any) -> (R | promiseBase))?
	) -> promiseBase,
	andThenReturn: <R>(value: R | promiseBase) -> promiseBase,
	await: () -> (boolean, any?),
	awaitResult: () -> result<T>,
	awaitStatus: () -> (promiseStatus, any?),
	cancel: (reason: any?) -> boolean,
	catch: <R>(onRejected: (reason: any) -> (R | promiseBase)) -> promiseBase,
	catchCancel: <R>(onCancelled: (reason: any?) -> (R | promiseBase)) -> promiseBase,
	catchCancelReturn: <R>(value: R | promiseBase) -> promiseBase,
	catchReturn: <R>(value: R | promiseBase) -> promiseBase,
	deadline: (deadlineTime: number, reason: any?) -> promise<T>,
	delay: (seconds: number) -> promise<T>,
	expect: (message: string?) -> T,
	finally: (callback: () -> any) -> promise<T>,
	fork: () -> promise<T>,
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
	onCancel: (callback: (reason: any?) -> ()) -> connection,
	observe: (
		onResolved: ((value: T) -> ())?,
		onRejected: ((reason: any) -> ())?,
		onCancelled: ((reason: any?) -> ())?
	) -> observer<T>,
	observeSettled: (callback: (resultValue: result<T>) -> ()) -> observer<T>,
	tap: (callback: (value: T) -> any) -> promise<T>,
	tapCancel: (callback: (reason: any?) -> any) -> promise<T>,
	tapError: (callback: (reason: any) -> any) -> promise<T>,
	tapSettled: (callback: (resultValue: result<T>) -> any) -> promise<T>,
	timeout: (seconds: number, options: timeoutOptions?) -> promise<T>,
	timeoutOr: <R>(seconds: number, fallback: R | promiseBase) -> promiseBase,
	toResult: () -> promiseBase,
	withCancellation: (token: cancellationToken) -> promise<T>,
}

export type deferred<T> = {
	cancel: (reason: any?) -> boolean,
	promise: promise<T>,
	reject: (reason: any) -> boolean,
	resolve: (value: T | promise<T>) -> boolean,
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
	adoptionSource: promiseContext?,
	cancelHandlers: {(reason: any?) -> ()},
	createdAt: number,
	id: number,
	isFlushing: boolean,
	isHandled: boolean,
	isResolutionLocked: boolean,
	isUnhandledReported: boolean,
	label: string?,
	rejectionHandlerCount: number,
	observers: {observerRecord},
	promiseValue: any?,
	reason: any?,
	settledAt: number?,
	status: promiseStatus,
	tokenConnection: {
		connected: boolean,
		disconnect: () -> boolean,
	}?,
	value: any?,
}

local promiseContextsStorage = setmetatable({}, {__mode = "k"})
local promiseContexts: {[any]: promiseContext} = promiseContextsStorage :: any

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

local scheduleUnhandledCheck: (context: promiseContext) -> ()

local function protectedCall(callback: any, ...: any): (boolean, any?)
	local results = table.pack(pcall(callback, ...))

	return results[1] == true, results[2]
end

--————————————————————————————————————————————————————————————————————--

local function disconnectObserver(context: promiseContext, observerValue: observerRecord): boolean
	if not observerValue.connected then return false end

	observerValue.connected = false

	if observerValue.handlesRejection and not observerValue.dispatched then
		context.rejectionHandlerCount -= 1
		assert(context.rejectionHandlerCount >= 0, "Promily rejection handler count became negative.")

		if context.status == status.rejected and not context.isHandled then
			scheduleUnhandledCheck(context)
		end
	end

	local connectionValue = observerValue.connectionValue

	if connectionValue then
		connectionValue.connected = false
	end

	local index = table.find(context.observers, observerValue)

	if index then
		table.remove(context.observers, index)
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

local function reportUnhandled(context: promiseContext)
	if context.status ~= status.rejected then return end
	if context.isHandled then return end
	if context.isUnhandledReported then return end
	if context.rejectionHandlerCount > 0 then return end

	local promiseValue = context.promiseValue
	if not promiseValue then return end

	context.isUnhandledReported = true

	local success, failure = protectedCall(
		unhandledRejectionHandler,
		promiseValue,
		context.reason
	)

	if success then return end

	warn("[Promily] Unhandled rejection handler failed:", failure)
end

--————————————————————————————————————————————————————————————————————--

scheduleUnhandledCheck = function(context: promiseContext)
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

	if observerValue.handlesRejection then
		context.rejectionHandlerCount -= 1
		assert(context.rejectionHandlerCount >= 0, "Promily rejection handler count became negative.")

		if context.status == status.rejected then
			context.isHandled = true
		end
	end

	local connectionValue = observerValue.connectionValue

	if connectionValue then
		connectionValue.connected = false
	end

	local callback: ((value: any) -> ())? = nil
	local callbackValue: any? = nil

	if context.status == status.resolved then
		callback = observerValue.onResolved
		callbackValue = context.value
	end

	if context.status == status.rejected then
		callback = observerValue.onRejected
		callbackValue = context.reason
	end

	if context.status == status.cancelled then
		callback = observerValue.onCancelled
		callbackValue = context.reason
	end

	if not callback then return end

	local success, failure = protectedCall(callback, callbackValue)

	if success then return end

	warn(`[Promily] Observer callback failed for promise #{context.id}:`, failure)
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

		local success, failure = protectedCall(callback, context.reason)

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
	context.settledAt = os.clock()
	context.adoptionSource = nil

	if nextStatus == status.cancelled then
		lifetimeCancelled += 1
	end

	if nextStatus == status.rejected then
		lifetimeRejected += 1
	end

	if nextStatus == status.resolved then
		lifetimeResolved += 1
	end

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
	local shouldHandleRejection: boolean

	if handlesRejection == nil then
		shouldHandleRejection = onRejected ~= nil
	else
		shouldHandleRejection = handlesRejection
	end

	if shouldHandleRejection then
		context.rejectionHandlerCount += 1
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
			return disconnectObserver(context, observerValue)
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

local function createsAdoptionCycle(context: promiseContext, sourceContext: promiseContext): boolean
	local current: promiseContext? = sourceContext
	local seen: {[any]: boolean} = {}

	while current do
		if current == context then return true end
		if seen[current] then return true end

		seen[current] = true
		current = current.adoptionSource
	end

	return false
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

	if createsAdoptionCycle(context, sourceContext) then
		return settle(
			context,
			status.rejected,
			nil,
			"Promily promise resolution cycle detected."
		)
	end

	context.adoptionSource = sourceContext

	local connectionValue: observer<any>?

	connectionValue = observeInternal(
		sourceContext,
		function(resolvedValue)
			if connectionValue then
				connectionValue.disconnect()
				connectionValue = nil
			end

			context.adoptionSource = nil
			resolveContext(context, resolvedValue)
		end,
		function(rejectionReason)
			if connectionValue then
				connectionValue.disconnect()
				connectionValue = nil
			end

			context.adoptionSource = nil
			settle(context, status.rejected, nil, rejectionReason)
		end,
		function(cancelReason)
			if connectionValue then
				connectionValue.disconnect()
				connectionValue = nil
			end

			context.adoptionSource = nil
			settle(context, status.cancelled, nil, cancelReason)
		end
	)

	context.cancelHandlers[#context.cancelHandlers + 1] = function(_reason)
		context.adoptionSource = nil

		if not connectionValue then return end

		connectionValue.disconnect()
		connectionValue = nil
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

local function createPending<T>(initialToken: cancellationToken?): (promise<T>, deferred<T>)
	nextPromiseId += 1

	local context: promiseContext = {
		adoptionSource = nil,
		cancelHandlers = {},
		createdAt = os.clock(),
		id = nextPromiseId,
		isFlushing = false,
		isHandled = false,
		isResolutionLocked = false,
		isUnhandledReported = false,
		label = nil,
		rejectionHandlerCount = 0,
		observers = {},
		promiseValue = nil,
		reason = nil,
		settledAt = nil,
		status = status.pending,
		tokenConnection = nil,
		value = nil,
	}

	lifetimeCreated += 1

	local promiseValue: promise<T>
	local deferredValue: deferred<T>

	local function resolve(value: T | promise<T>): boolean
		if context.status ~= status.pending then return false end
		if context.isResolutionLocked then return false end

		context.isResolutionLocked = true

		return resolveContext(context, value)
	end

	local function reject(reason: any): boolean
		if context.isResolutionLocked then return false end

		return settle(context, status.rejected, nil, reason)
	end

	--- Cancels this Promise if it is still pending.
	---@param reason any? Optional cancellation reason.
	---@return boolean didCancel True when this call performed the cancellation.
	local function cancel(reason: any?): boolean
		return settle(context, status.cancelled, nil, reason)
	end

	--- Subscribes to Promise settlement without creating a child Promise.
	---@param onResolved fun(value: T)? Resolution observer.
	---@param onRejected fun(reason: any)? Rejection observer.
	---@param onCancelled fun(reason: any?)? Cancellation observer.
	---@return observer<T> observerValue Disconnectable observer.
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

	local function buildResult(): result<T>
		local now = os.clock()
		local endTime: number

		if context.settledAt == nil then
			endTime = now
		else
			endTime = context.settledAt
		end

		return {
			createdAt = context.createdAt,
			id = context.id,
			isSettled = context.status ~= status.pending,
			label = context.label,
			pendingFor = math.max(endTime - context.createdAt, 0),
			reason = context.reason,
			settledAt = context.settledAt,
			status = context.status,
			value = context.value,
		}
	end

	--- Subscribes once to any settlement and receives a structured result snapshot.
	---@param callback fun(resultValue: result<T>) Settlement observer.
	---@return observer<T> observerValue Disconnectable observer.
	local function observeSettled(
		callback: (resultValue: result<T>) -> ()
	): observer<T>
		return observeInternal(
			context,
			function()
				callback(buildResult())
			end,
			function()
				callback(buildResult())
			end,
			function()
				callback(buildResult())
			end,
			false
		) :: observer<T>
	end

--————————————————————————————————————————————————————————————————————--

	--- Creates a child Promise from resolution or rejection callbacks.
	---@generic R
	---@param onResolved fun(value: T): R | promise<R>? Optional resolution callback.
	---@param onRejected fun(reason: any): R | promise<R>? Optional rejection callback.
	---@return promise<R> promiseValue Chained Promise.
	local function andThen<R>(
		onResolved: ((value: T) -> (R | promise<R>))?,
		onRejected: ((reason: any) -> (R | promise<R>))?
	): promise<R>
		local childPromise, childDeferred = createPending<<R>>()
		local parentObserver: observer<T>?

		local function resolveChildWithCallback(callback: (value: any) -> any, input: any)
			local success, output = protectedCall(callback, input)

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

	--- Recovers from rejection while leaving cancellation distinct.
	---@generic R
	---@param onRejected fun(reason: any): R | promise<R> Rejection recovery callback.
	---@return promise<T | R> promiseValue Recovered Promise.
	local function catch<R>(onRejected: (reason: any) -> (R | promise<R>)): promise<T | R>
		return andThen(nil, onRejected) :: promise<T | R>
	end

	--- Recovers from the distinct Promily cancellation state.
	---@generic R
	---@param onCancelled fun(reason: any?): R | promise<R> Cancellation recovery callback.
	---@return promise<T | R> promiseValue Recovered Promise.
	local function catchCancel<R>(
		onCancelled: (reason: any?) -> (R | promise<R>)
	): promise<T | R>
		local childPromise, childDeferred = createPending<<T | R>>()
		local parentObserver: observer<T>?

		parentObserver = observe(
			function(value: T)
				childDeferred.resolve(value)
			end,
			function(reasonValue: any)
				childDeferred.reject(reasonValue)
			end,
			function(reasonValue: any?)
				local success, output = protectedCall(onCancelled, reasonValue)

				if not success then
					childDeferred.reject(output)
					return
				end

				childDeferred.resolve(output :: any)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if not parentObserver then return end

			parentObserver.disconnect()
			parentObserver = nil
		end

		return childPromise
	end

	--- Runs cleanup after resolution, rejection, or cancellation and preserves settlement when cleanup succeeds.
	---@param callback fun(): any Cleanup callback.
	---@return promise<T> promiseValue Promise that waits for cleanup.
	local function finally(callback: () -> any): promise<T>
		local childPromise, childDeferred = createPending<<T>>()
		local cleanupObserver: observer<any>?
		local parentObserver: observer<T>?

		local function runFinally(nextStatus: promiseStatus, settledValue: any?)
			local success, callbackResult = protectedCall(callback)

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

	--- Creates a consumer branch whose cancellation never cancels the source Promise.
	---@return promise<T> branch Independent consumer branch.
	local function fork(): promise<T>
		local childPromise, childDeferred = createPending<<T>>()
		local parentObserver: observer<T>?

		parentObserver = observe(
			function(value: T)
				childDeferred.resolve(value)
			end,
			function(reasonValue: any)
				childDeferred.reject(reasonValue)
			end,
			function(reasonValue: any?)
				childDeferred.cancel(reasonValue)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if not parentObserver then return end

			parentObserver.disconnect()
			parentObserver = nil
		end

		return childPromise
	end

--————————————————————————————————————————————————————————————————————--

	--- Runs a resolution side effect while preserving the resolved value.
	---@param callback fun(value: T): any Resolution side-effect callback.
	---@return promise<T> promiseValue Promise preserving the source value.
	local function tap(callback: (value: T) -> any): promise<T>
		return andThen(function(value: T)
			local success, callbackResult = protectedCall(callback, value)

			if not success then
				return module.reject(callbackResult) :: any
			end

			return module.resolve(callbackResult).andThen(function()
				return value
			end)
		end) :: promise<T>
	end

	--- Runs a rejection side effect while preserving the rejection when the side effect succeeds.
	---@param callback fun(reason: any): any Rejection side-effect callback.
	---@return promise<T> promiseValue Promise preserving the source rejection.
	local function tapError(callback: (reason: any) -> any): promise<T>
		return catch(function(reasonValue: any)
			local success, callbackResult = protectedCall(callback, reasonValue)

			if not success then
				return module.reject(callbackResult)
			end

			return module.resolve(callbackResult).andThen(function()
				return module.reject(reasonValue)
			end)
		end) :: promise<T>
	end

	--- Runs a side effect only when the source is cancelled while preserving cancellation.
	---@param callback fun(reason: any?): any Cancellation side-effect callback.
	---@return promise<T> promiseValue Promise preserving the source settlement.
	local function tapCancel(callback: (reason: any?) -> any): promise<T>
		return finally(function()
			if context.status ~= status.cancelled then return nil end

			return callback(context.reason)
		end)
	end

	--- Runs a side effect after any settlement while preserving the source settlement.
	---@param callback fun(resultValue: result<T>): any Settlement side-effect callback.
	---@return promise<T> promiseValue Promise preserving the source settlement.
	local function tapSettled(callback: (resultValue: result<T>) -> any): promise<T>
		return finally(function()
			return callback(buildResult())
		end)
	end

	--- Replaces a successful resolution with a fixed value or Promise.
	---@generic R
	---@param value R | promise<R> Replacement result.
	---@return promise<R> promiseValue Chained Promise.
	local function andThenReturn<R>(value: R | promise<R>): promise<R>
		return andThen(function()
			return value
		end)
	end

	--- Replaces rejection with a fixed value or Promise.
	---@generic R
	---@param value R | promise<R> Rejection fallback.
	---@return promise<T | R> promiseValue Promise with rejection recovery.
	local function catchReturn<R>(value: R | promise<R>): promise<T | R>
		return catch(function()
			return value
		end)
	end

	--- Replaces cancellation with a fixed value or Promise.
	---@generic R
	---@param value R | promise<R> Cancellation fallback.
	---@return promise<T | R> promiseValue Promise with cancellation recovery.
	local function catchCancelReturn<R>(value: R | promise<R>): promise<T | R>
		return catchCancel(function()
			return value
		end)
	end

	--- Returns the current Promise state.
	---@return promiseStatus statusValue Current status.
	local function getStatus(): promiseStatus
		return context.status
	end

	--- Reports whether the Promise is still pending.
	---@return boolean isPendingValue True while pending.
	local function isPending(): boolean
		return context.status == status.pending
	end

	--- Reports whether the Promise resolved successfully.
	---@return boolean isResolvedValue True after resolution.
	local function isResolved(): boolean
		return context.status == status.resolved
	end

	--- Reports whether the Promise rejected.
	---@return boolean isRejectedValue True after rejection.
	local function isRejected(): boolean
		return context.status == status.rejected
	end

	--- Reports whether the Promise was cancelled.
	---@return boolean isCancelledValue True after cancellation.
	local function isCancelled(): boolean
		return context.status == status.cancelled
	end

	--- Reports whether the Promise is no longer pending.
	---@return boolean isSettledValue True after any settlement.
	local function isSettled(): boolean
		return context.status ~= status.pending
	end

	--- Returns a non-yielding structured snapshot of this Promise.
	---@return result<T> resultValue Current Promise snapshot.
	local function inspect(): result<T>
		return buildResult()
	end

	--- Yields until settlement and returns the exact Promily status plus value or reason.
	---@return promiseStatus statusValue Final status.
	---@return any? valueOrReason Resolved value, rejection reason, or cancellation reason.
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

	--- Yields until settlement and reports success only for resolution.
	---@return boolean success True when resolved.
	---@return any? valueOrReason Resolved value or failure reason.
	local function await(): (boolean, any?)
		local settledStatus, settledValue = awaitStatus()

		return settledStatus == status.resolved, settledValue
	end

	--- Yields until settlement and returns a structured result.
	---@return result<T> resultValue Final Promise result.
	local function awaitResult(): result<T>
		awaitStatus()

		return inspect()
	end

	--- Yields for resolution and throws when the Promise rejects or is cancelled.
	---@param message string? Optional replacement error message.
	---@return T value Resolved value.
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

	--- Assigns a diagnostic label and returns this Promise.
	---@param name string Diagnostic label.
	---@return promise<T> promiseValue This Promise.
	local function label(name: string): promise<T>
		assert(name ~= "", "Promily promise label cannot be empty.")

		context.label = name

		return promiseValue
	end

	--- Registers cancellation cleanup and returns a disconnectable connection.
	---@param callback fun(reason: any?) Cancellation callback.
	---@return connection connectionValue Cancellation connection.
	local function onCancel(callback: (reason: any?) -> ()): connection
		return observeInternal(
			context,
			nil,
			nil,
			callback,
			false
		) :: connection
	end

	--- Returns the diagnostic label when one has been assigned.
	---@return string? labelValue Current label.
	local function getLabel(): string?
		return context.label
	end

	--- Returns the unique runtime Promise identifier.
	---@return number id Promise identifier.
	local function getId(): number
		return context.id
	end

	--- Delays delivery of this Promise settlement without cancelling the source.
	---@param seconds number Non-negative delay in seconds.
	---@return promise<T> promiseValue Delayed consumer Promise.
	local function delay(seconds: number): promise<T>
		assert(seconds == seconds and seconds < math.huge and seconds >= 0, "Promily delay must be finite and non-negative.")

		local childPromise, childDeferred = createPending<<T>>()
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

	--- Creates a consumer that rejects or falls back when the relative timeout expires.
	---@param seconds number Non-negative timeout duration.
	---@param options timeoutOptions? Optional reason or fallback behavior.
	---@return promise<T> promiseValue Timeout-bound consumer Promise.
	local function timeout(seconds: number, options: timeoutOptions?): promise<T>
		assert(seconds == seconds and seconds < math.huge and seconds >= 0, "Promily timeout must be finite and non-negative.")

		local childPromise, childDeferred = createPending<<T>>()
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

	--- Creates a consumer bounded by an absolute os.clock() deadline.
	---@param deadlineTime number Absolute os.clock() deadline.
	---@param reason any? Optional deadline rejection reason.
	---@return promise<T> promiseValue Deadline-bound consumer Promise.
	local function deadline(deadlineTime: number, reason: any?): promise<T>
		assert(
			deadlineTime == deadlineTime and deadlineTime > -math.huge and deadlineTime < math.huge,
			"Promily deadline must be finite."
		)

		local remaining = math.max(deadlineTime - os.clock(), 0)
		local deadlineReason = reason

		if deadlineReason == nil then
			deadlineReason = `Promily promise exceeded deadline {deadlineTime}.`
		end

		return timeout(remaining, {
			reason = deadlineReason,
		})
	end

	--- Resolves with a fallback if the source does not settle before the timeout.
	---@generic R
	---@param seconds number Non-negative timeout duration.
	---@param fallback R | promise<R> Timeout fallback.
	---@return promise<T | R> promiseValue Source-or-fallback Promise.
	local function timeoutOr<R>(seconds: number, fallback: R | promise<R>): promise<T | R>
		return timeout(seconds, {
			fallback = fallback,
			hasFallback = true,
		}) :: promise<T | R>
	end

	--- Creates a consumer branch cancelled by the supplied token without cancelling the source.
	---@param token cancellationToken Consumer cancellation token.
	---@return promise<T> promiseValue Token-bound consumer Promise.
	local function withCancellation(token: cancellationToken): promise<T>
		local childPromise, childDeferred = createPending<<T>>()
		local parentObserver: observer<T>?
		local tokenConnection: connection?
		local stopped = false

		local function cleanup()
			if parentObserver then
				parentObserver.disconnect()
				parentObserver = nil
			end

			if tokenConnection then
				tokenConnection.disconnect()
				tokenConnection = nil
			end
		end

		local function cancelFromToken(reasonValue: any?)
			if stopped then return end

			stopped = true
			cleanup()
			childDeferred.cancel(reasonValue)
		end

		if token.isCancelled() then
			cancelFromToken(token.getReason())
			return childPromise
		end

		tokenConnection = token.onCancelled(cancelFromToken)

		if token.isCancelled() then
			cancelFromToken(token.getReason())
			return childPromise
		end

		parentObserver = observe(
			function(value: T)
				if stopped then return end

				stopped = true
				cleanup()
				childDeferred.resolve(value)
			end,
			function(reasonValue: any)
				if stopped then return end

				stopped = true
				cleanup()
				childDeferred.reject(reasonValue)
			end,
			function(reasonValue: any?)
				if stopped then return end

				stopped = true
				cleanup()
				childDeferred.cancel(reasonValue)
			end
		)

		local childContext = getContext(childPromise)

		childContext.cancelHandlers[#childContext.cancelHandlers + 1] = function(_reason)
			if stopped then return end

			stopped = true
			cleanup()
		end

		return childPromise
	end

	--- Converts any settlement into a resolved structured result.
	---@return promise<result<T>> promiseValue Promise resolving with the settlement snapshot.
	local function toResult(): promise<result<T>>
		local childPromise, childDeferred = createPending<<result<T>>>()
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

	promiseValue = ({
		andThen = andThen,
		andThenReturn = andThenReturn,
		await = await,
		awaitResult = awaitResult,
		awaitStatus = awaitStatus,
		cancel = cancel,
		catch = catch,
		catchCancel = catchCancel,
		catchCancelReturn = catchCancelReturn,
		catchReturn = catchReturn,
		deadline = deadline,
		delay = delay,
		expect = expect,
		finally = finally,
		fork = fork,
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
		onCancel = onCancel,
		observe = observe,
		observeSettled = observeSettled,
		tap = tap,
		tapCancel = tapCancel,
		tapError = tapError,
		tapSettled = tapSettled,
		timeout = timeout,
		timeoutOr = timeoutOr,
		toResult = toResult,
		withCancellation = withCancellation,
	} :: any) :: promise<T>

	context.promiseValue = promiseValue
	promiseContexts[promiseValue] = context

	deferredValue = {
		cancel = cancel,
		promise = promiseValue,
		reject = reject,
		resolve = resolve,
	}

	if initialToken and initialToken.isCancelled() then
		cancel(initialToken.getReason())
	end

	if initialToken and not initialToken.isCancelled() then
		context.tokenConnection = initialToken.onCancelled(function(reasonValue)
			cancel(reasonValue)
		end)
	end

	return promiseValue, deferredValue
end

--————————————————————————————————————————————————————————————————————--

--- Creates a Promise and schedules its executor asynchronously.
---@generic T
---@param executor fun(resolve: fun(value: T | promise<T>), reject: fun(reason: any), onCancel: fun(callback: fun(reason: any?)): boolean) Promise executor.
---@param token cancellationToken? Optional cancellation token.
---@return promise<T> promiseValue Created Promise.
function module.new<T>(
	executor: (
		resolve: (value: T | promise<T>) -> (),
		reject: (reason: any) -> (),
		onCancel: (callback: (reason: any?) -> ()) -> boolean
	) -> (),
	token: cancellationToken?
): promise<T>
	local promiseValue, deferredValue = createPending<<T>>(token)
	local context = getContext(promiseValue)

	task.spawn(function()
		if context.status ~= status.pending then return end

		local function onCancel(callback: (reason: any?) -> ()): boolean
			if context.status == status.cancelled then
				task.defer(function()
					local success, failure = protectedCall(callback, context.reason)

					if success then return end

					warn("[Promily] Cancellation handler failed:", failure)
				end)

				return false
			end

			if context.status ~= status.pending then return false end

			context.cancelHandlers[#context.cancelHandlers + 1] = callback

			return true
		end

		local success, failure = protectedCall(
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

--- Creates a deferred Promise with explicit settlement controls.
---@generic T
---@param token cancellationToken? Optional cancellation token.
---@return deferred<T> deferredValue Deferred controller and Promise.
function module.defer<T>(token: cancellationToken?): deferred<T>
	local _, deferredValue = createPending<<T>>(token)

	return deferredValue
end

--————————————————————————————————————————————————————————————————————--

--- Returns an existing Promily Promise unchanged or wraps a value in a resolved Promise.
---@generic T
---@param value T | promise<T> Value or existing Promise.
---@return promise<T> promiseValue Resolved or existing Promise.
function module.resolve<T>(value: T | promise<T>): promise<T>
	if isPromise(value) then
		return value :: promise<T>
	end

	local promiseValue, deferredValue = createPending<<T>>()
	deferredValue.resolve(value)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

--- Creates an immediately rejected Promise.
---@generic T
---@param reason any Rejection reason.
---@return promise<T> promiseValue Rejected Promise.
function module.reject<T>(reason: any): promise<T>
	local promiseValue, deferredValue = createPending<<T>>()
	deferredValue.reject(reason)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

--- Creates an immediately cancelled Promise.
---@generic T
---@param reason any? Cancellation reason.
---@return promise<T> promiseValue Cancelled Promise.
function module.cancelled<T>(reason: any?): promise<T>
	local promiseValue, deferredValue = createPending<<T>>()
	deferredValue.cancel(reason)

	return promiseValue
end

--————————————————————————————————————————————————————————————————————--

--- Executes a callback inside Promise error handling and adopts its returned Promise when needed.
---@generic T
---@param callback fun(): T | promise<T> Callback to execute.
---@param token cancellationToken? Optional cancellation token.
---@return promise<T> promiseValue Promise for the callback result.
function module.try<T>(
	callback: () -> (T | promise<T>),
	token: cancellationToken?
): promise<T>
	return module.new(function(resolve, reject)
		local success, output = protectedCall(callback)

		if not success then
			reject(output)
			return
		end

		resolve(output)
	end, token)
end

--————————————————————————————————————————————————————————————————————--

--- Converts a throwing function into a function that always returns a Promily Promise.
---@param callback fun(...: any): any Function to wrap.
---@return fun(...: any): promise<any> wrapped Promise-returning function.
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

--- Checks whether a value is a Promily Promise.
---@param value any Value to inspect.
---@return boolean isPromiseValue Whether the value is a Promily Promise.
function module.is(value: any): boolean
	return isPromise(value)
end

--————————————————————————————————————————————————————————————————————--

--- Returns live pending Promise snapshots sorted longest-pending first.
---@param limit number? Optional maximum result count.
---@return {diagnosticsSnapshot} snapshots Pending Promise snapshots.
function module.getPendingSnapshots(limit: number?): {diagnosticsSnapshot}
	if limit ~= nil then
		assert(
			limit == limit and limit < math.huge and limit >= 0 and limit % 1 == 0,
			"Promily diagnostics limit must be a finite non-negative integer."
		)
	end

	local now = os.clock()
	local snapshots: {diagnosticsSnapshot} = {}

	for _, context in promiseContexts do
		if context.status ~= status.pending then continue end

		snapshots[#snapshots + 1] = {
			createdAt = context.createdAt,
			id = context.id,
			isSettled = false,
			label = context.label,
			pendingFor = math.max(now - context.createdAt, 0),
			reason = nil,
			settledAt = nil,
			status = status.pending,
			value = nil,
		}
	end

	table.sort(snapshots, function(a, b)
		if a.pendingFor == b.pendingFor then
			return a.id < b.id
		end

		return a.pendingFor > b.pendingFor
	end)

	if limit == nil or #snapshots <= limit then
		return snapshots
	end

	local limited: {diagnosticsSnapshot} = table.create(limit)

	for index = 1, limit do
		limited[index] = snapshots[index]
	end

	return limited
end

--————————————————————————————————————————————————————————————————————--

--- Returns lifetime and currently-live Promise diagnostic counters.
---@return diagnosticsStats stats Promise diagnostics.
function module.getDiagnosticsStats(): diagnosticsStats
	local liveCancelled = 0
	local livePending = 0
	local liveRejected = 0
	local liveResolved = 0
	local liveTotal = 0

	for _, context in promiseContexts do
		liveTotal += 1

		if context.status == status.cancelled then
			liveCancelled += 1
		end

		if context.status == status.pending then
			livePending += 1
		end

		if context.status == status.rejected then
			liveRejected += 1
		end

		if context.status == status.resolved then
			liveResolved += 1
		end
	end

	return {
		created = lifetimeCreated,
		liveCancelled = liveCancelled,
		livePending = livePending,
		liveRejected = liveRejected,
		liveResolved = liveResolved,
		liveTotal = liveTotal,
		totalCancelled = lifetimeCancelled,
		totalRejected = lifetimeRejected,
		totalResolved = lifetimeResolved,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Returns the frozen table of canonical Promise status strings.
---@return any statusTable Frozen Promise status table.
function module.getStatusTable()
	return status
end

--————————————————————————————————————————————————————————————————————--

--- Replaces the global otherwise-unhandled rejection callback.
---@param callback fun(promiseValue: promise<any>, reason: any) Unhandled rejection callback.
function module.setUnhandledRejectionHandler(
	callback: (promiseValue: any, reason: any) -> ()
)
	unhandledRejectionHandler = callback
end

--————————————————————————————————————————————————————————————————————--

return module
