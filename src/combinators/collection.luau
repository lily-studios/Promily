--!strict

-- implements Promily collection combinators without polling or permanent runtime loops

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
local errors = require(core:WaitForChild("errors"))
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type settledResult<T> = {
	reason: any?,
	status: promiseModule.promiseStatus,
	value: T?,
}

export type mapOptions = {
	concurrency: number?,
}

export type partitionResult<T> = {
	matched: {T},
	unmatched: {T},
}

type filterDecision<T> = {
	include: boolean,
	value: T,
}

--————————————————————————————————————————————————————————————————————--

local function disconnectObservers(observers: {promiseModule.observer<any>})
	for _, observerValue in observers do
		observerValue.disconnect()
	end

	table.clear(observers)
end

local function chain<T, R>(
	source: promiseModule.promise<T>,
	onResolved: (value: T) -> (R | promiseModule.promise<R>)
): promiseModule.promise<R>
	return source.andThen(onResolved) :: any
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when every input resolves and preserves input order.
---@generic T
---@param values {T | promiseModule.promise<T>} Input values or Promises.
---@return promiseModule.promise<{T}> promiseValue Promise containing all resolved values.
function module.all<T>(values: {T | promiseModule.promise<T>}): promiseModule.promise<{T}>
	if #values == 0 then
		return promiseModule.resolve({})
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local remaining = #values
		local results: {T} = table.create(#values)
		local settled = false

		local function finishRejected(reason: any)
			if settled then return end

			settled = true
			disconnectObservers(observers)
			reject(reason)
		end

		local function finishCancelled(reason: any?)
			if settled then return end

			settled = true
			disconnectObservers(observers)
			reject(errors.cancelledInput(reason))
		end

		onCancel(function(_reason)
			settled = true
			disconnectObservers(observers)
		end)

		for index, value in values do
			local source = promiseModule.resolve(value)

			local observerValue = source.observe(
				function(resolvedValue: T)
					if settled then return end

					results[index] = resolvedValue
					remaining -= 1

					if remaining > 0 then return end

					settled = true
					disconnectObservers(observers)
					resolve(results)
				end,
				finishRejected,
				finishCancelled
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Waits for every input and captures each resolution, rejection, or cancellation.
---@generic T
---@param values {T | promiseModule.promise<T>} Input values or Promises.
---@return promiseModule.promise<{settledResult<T>}> promiseValue Promise containing settlements in input order.
function module.allSettled<T>(
	values: {T | promiseModule.promise<T>}
): promiseModule.promise<{settledResult<T>}>
	if #values == 0 then
		return promiseModule.resolve({})
	end

	return promiseModule.new(function(resolve, _reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local remaining = #values
		local results: {settledResult<T>} = table.create(#values)
		local stopped = false

		local function complete(index: number, resultValue: settledResult<T>)
			if stopped then return end

			results[index] = resultValue
			remaining -= 1

			if remaining > 0 then return end

			stopped = true
			disconnectObservers(observers)
			resolve(results)
		end

		onCancel(function(_reason)
			stopped = true
			disconnectObservers(observers)
		end)

		for index, value in values do
			local source = promiseModule.resolve(value)

			local observerValue = source.observe(
				function(resolvedValue: T)
					complete(index, {
						reason = nil,
						status = "Resolved",
						value = resolvedValue,
					})
				end,
				function(reason: any)
					complete(index, {
						reason = reason,
						status = "Rejected",
						value = nil,
					})
				end,
				function(reason: any?)
					complete(index, {
						reason = reason,
						status = "Cancelled",
						value = nil,
					})
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Settles with the first input to settle.
---@generic T
---@param values {T | promiseModule.promise<T>} Input values or Promises.
---@return promiseModule.promise<T> promiseValue First settlement.
function module.race<T>(values: {T | promiseModule.promise<T>}): promiseModule.promise<T>
	if #values == 0 then
		return promiseModule.reject("Promily.race() requires at least one value.")
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local settled = false

		local function stop()
			disconnectObservers(observers)
		end

		onCancel(function(_reason)
			settled = true
			stop()
		end)

		for _, value in values do
			local source = promiseModule.resolve(value)

			local observerValue = source.observe(
				function(resolvedValue: T)
					if settled then return end

					settled = true
					stop()
					resolve(resolvedValue)
				end,
				function(reason: any)
					if settled then return end

					settled = true
					stop()
					reject(reason)
				end,
				function(reason: any?)
					if settled then return end

					settled = true
					stop()
					reject(errors.cancelledInput(reason))
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves with the first successful input or rejects with AggregateError after all inputs fail.
---@generic T
---@param values {T | promiseModule.promise<T>} Input values or Promises.
---@return promiseModule.promise<T> promiseValue First successful value.
function module.any<T>(values: {T | promiseModule.promise<T>}): promiseModule.promise<T>
	if #values == 0 then
		return promiseModule.reject(errors.aggregate({}))
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local reasons: {any} = table.create(#values)
		local remaining = #values
		local settled = false

		local function fail(index: number, reason: any)
			if settled then return end

			reasons[index] = reason
			remaining -= 1

			if remaining > 0 then return end

			settled = true
			disconnectObservers(observers)
			reject(errors.aggregate(reasons))
		end

		onCancel(function(_reason)
			settled = true
			disconnectObservers(observers)
		end)

		for index, value in values do
			local source = promiseModule.resolve(value)

			local observerValue = source.observe(
				function(resolvedValue: T)
					if settled then return end

					settled = true
					disconnectObservers(observers)
					resolve(resolvedValue)
				end,
				function(reason: any)
					fail(index, reason)
				end,
				function(reason: any?)
					fail(index, errors.cancelledInput(reason))
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves after the requested number of inputs resolve successfully.
---@generic T
---@param values {T | promiseModule.promise<T>} Input values or Promises.
---@param count number Required number of successful resolutions.
---@return promiseModule.promise<{T}> promiseValue Successful values in settlement order.
function module.some<T>(
	values: {T | promiseModule.promise<T>},
	count: number
): promiseModule.promise<{T}>
	assert(count == count and count < math.huge and count >= 0 and count % 1 == 0, "Promily.some() count must be a finite non-negative integer.")

	if count == 0 then
		return promiseModule.resolve({})
	end

	if count > #values then
		return promiseModule.reject(errors.insufficientInputs(count, #values))
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local failures: {any} = {}
		local requiredFailures = #values - count + 1
		local resolvedValues: {T} = table.create(count)
		local settled = false

		local function fail(reason: any)
			if settled then return end

			failures[#failures + 1] = reason

			if #failures < requiredFailures then return end

			settled = true
			disconnectObservers(observers)
			reject(errors.aggregate(failures))
		end

		onCancel(function(_reason)
			settled = true
			disconnectObservers(observers)
		end)

		for _, value in values do
			local source = promiseModule.resolve(value)

			local observerValue = source.observe(
				function(resolvedValue: T)
					if settled then return end

					resolvedValues[#resolvedValues + 1] = resolvedValue

					if #resolvedValues < count then return end

					settled = true
					disconnectObservers(observers)
					resolve(resolvedValues)
				end,
				fail,
				function(reason: any?)
					fail(errors.cancelledInput(reason))
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves all string-keyed values while preserving their keys.
---@generic T
---@param values {[string]: T | promiseModule.promise<T>} Keyed values or Promises.
---@return promiseModule.promise<{[string]: T}> promiseValue Resolved keyed values.
function module.props<T>(
	values: {[string]: T | promiseModule.promise<T>}
): promiseModule.promise<{[string]: T}>
	local keys: {string} = {}

	for key in values do
		keys[#keys + 1] = key
	end

	if #keys == 0 then
		return promiseModule.resolve({})
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local remaining = #keys
		local results: {[string]: T} = {}
		local settled = false

		local function stop()
			disconnectObservers(observers)
		end

		onCancel(function(_reason)
			settled = true
			stop()
		end)

		for _, key in keys do
			local source = promiseModule.resolve(values[key])

			local observerValue = source.observe(
				function(resolvedValue: T)
					if settled then return end

					results[key] = resolvedValue
					remaining -= 1

					if remaining > 0 then return end

					settled = true
					stop()
					resolve(results)
				end,
				function(reason: any)
					if settled then return end

					settled = true
					stop()
					reject(reason)
				end,
				function(reason: any?)
					if settled then return end

					settled = true
					stop()
					reject(errors.cancelledInput(reason))
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Maps values with optional bounded concurrency while preserving input order.
---@generic T
---@generic R
---@param values {T} Values to map.
---@param mapper fun(value: T, index: number): R | promiseModule.promise<R> Mapper callback.
---@param options mapOptions? Optional concurrency limit.
---@return promiseModule.promise<{R}> promiseValue Mapped values in input order.
function module.map<T, R>(
	values: {T},
	mapper: (value: T, index: number) -> (R | promiseModule.promise<R>),
	options: mapOptions?
): promiseModule.promise<{R}>
	local total = #values

	if total == 0 then
		return promiseModule.resolve({})
	end

	local concurrency = total

	if options and options.concurrency then
		concurrency = options.concurrency
	end

	assert(
		concurrency == concurrency and concurrency < math.huge and concurrency >= 1 and concurrency % 1 == 0,
		"Promily.map() concurrency must be a finite positive integer."
	)

	concurrency = math.min(concurrency, total)

	return promiseModule.new(function(resolve, reject, onCancel)
		local active = 0
		local completed = 0
		local nextIndex = 1
		local observers: {promiseModule.observer<any>} = {}
		local activePromises: {[promiseModule.promise<any>]: boolean} = {}
		local results: {R} = table.create(total)
		local stopped = false

		local startNext: () -> ()

		local function cancelActive(reason: any?)
			for promiseValue in activePromises do
				promiseValue.cancel(reason)
			end

			table.clear(activePromises)
		end

		local function stop(reason: any)
			if stopped then return end

			stopped = true
			disconnectObservers(observers)
			cancelActive(reason)
			reject(reason)
		end

		startNext = function()
			if stopped then return end

			local availableSlots = concurrency - active
			local remainingInputs = total - nextIndex + 1
			local startCount = math.min(availableSlots, remainingInputs)

			for _ = 1, startCount do
				local index = nextIndex
				nextIndex += 1
				active += 1

				local mappedPromise = promiseModule.try(function()
					return mapper(values[index], index)
				end)

				activePromises[mappedPromise :: promiseModule.promise<any>] = true

				local observerValue = mappedPromise.observe(
					function(resolvedValue: R)
						activePromises[mappedPromise :: promiseModule.promise<any>] = nil

						if stopped then return end

						active -= 1
						completed += 1
						results[index] = resolvedValue

						if completed >= total then
							stopped = true
							disconnectObservers(observers)
							resolve(results)
							return
						end

						startNext()
					end,
					function(reason: any)
						activePromises[mappedPromise :: promiseModule.promise<any>] = nil
						stop(reason)
					end,
					function(reason: any?)
						activePromises[mappedPromise :: promiseModule.promise<any>] = nil
						stop(errors.cancelledMapper(reason))
					end
				)

				observers[#observers + 1] = observerValue :: promiseModule.observer<any>
			end
		end

		onCancel(function(reason)
			if stopped then return end

			stopped = true
			disconnectObservers(observers)
			cancelActive(reason)
		end)

		startNext()
	end)
end


--————————————————————————————————————————————————————————————————————--

--- Maps every value while collecting mapper resolution, rejection, and cancellation results.
---@generic T
---@generic R
---@param values {T} Values to map.
---@param mapper fun(value: T, index: number): R | promise<R> Mapper invoked for each value.
---@param options mapOptions? Optional concurrency limit.
---@return promise<{settledResult<R>}> results Settled mapper results in input order.
function module.mapSettled<T, R>(
	values: {T},
	mapper: (value: T, index: number) -> (R | promiseModule.promise<R>),
	options: mapOptions?
): promiseModule.promise<{settledResult<R>}>
	local total = #values

	if total == 0 then
		return promiseModule.resolve({})
	end

	local concurrency = total

	if options and options.concurrency then
		concurrency = options.concurrency
	end

	assert(
		concurrency == concurrency and concurrency < math.huge and concurrency >= 1 and concurrency % 1 == 0,
		"Promily.mapSettled() concurrency must be a finite positive integer."
	)

	concurrency = math.min(concurrency, total)

	return promiseModule.new(function(resolve, _reject, onCancel)
		local active = 0
		local completed = 0
		local nextIndex = 1
		local observers: {promiseModule.observer<any>} = {}
		local activePromises: {[promiseModule.promise<any>]: boolean} = {}
		local results: {settledResult<R>} = table.create(total)
		local stopped = false

		local startNext: () -> ()

		local function cancelActive(reason: any?)
			for promiseValue in activePromises do
				promiseValue.cancel(reason)
			end

			table.clear(activePromises)
		end

		local function complete(index: number, resultValue: settledResult<R>)
			if stopped then return end

			active -= 1
			completed += 1
			results[index] = resultValue

			if completed >= total then
				stopped = true
				disconnectObservers(observers)
				resolve(results)
				return
			end

			startNext()
		end

		startNext = function()
			if stopped then return end

			local availableSlots = concurrency - active
			local remainingInputs = total - nextIndex + 1
			local startCount = math.min(availableSlots, remainingInputs)

			for _ = 1, startCount do
				local index = nextIndex
				nextIndex += 1
				active += 1

				local mappedPromise = promiseModule.try(function()
					return mapper(values[index], index)
				end)

				activePromises[mappedPromise :: promiseModule.promise<any>] = true

				local observerValue = mappedPromise.observe(
					function(resolvedValue: R)
						activePromises[mappedPromise :: promiseModule.promise<any>] = nil
						complete(index, {
							reason = nil,
							status = "Resolved",
							value = resolvedValue,
						})
					end,
					function(reason: any)
						activePromises[mappedPromise :: promiseModule.promise<any>] = nil
						complete(index, {
							reason = reason,
							status = "Rejected",
							value = nil,
						})
					end,
					function(reason: any?)
						activePromises[mappedPromise :: promiseModule.promise<any>] = nil
						complete(index, {
							reason = reason,
							status = "Cancelled",
							value = nil,
						})
					end
				)

				observers[#observers + 1] = observerValue :: promiseModule.observer<any>
			end
		end

		onCancel(function(reason)
			if stopped then return end

			stopped = true
			disconnectObservers(observers)
			cancelActive(reason)
		end)

		startNext()
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Filters values with a synchronous or asynchronous predicate while preserving input order.
---@generic T
---@param values {T} Values to filter.
---@param predicate fun(value: T, index: number): boolean | promise<boolean> Predicate invoked for each value.
---@param options mapOptions? Optional concurrency limit.
---@return promise<{T}> values Values whose predicate resolved to true.
function module.filter<T>(
	values: {T},
	predicate: (value: T, index: number) -> (boolean | promiseModule.promise<boolean>),
	options: mapOptions?
): promiseModule.promise<{T}>
	local decisionsPromise = module.map(values, function(value: T, index: number)
		return chain(promiseModule.resolve(predicate(value, index)), function(include: boolean): filterDecision<T>
			return {
				include = include,
				value = value,
			}
		end)
	end, options)

	return chain(decisionsPromise, function(decisions: {filterDecision<T>})
		local filtered: {T} = {}

		for _, decision in decisions do
			if not decision.include then continue end

			filtered[#filtered + 1] = decision.value
		end

		return filtered
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Finds the first input-order value whose synchronous or asynchronous predicate resolves true.
--- All required predicate work follows the same optional concurrency bound as map().
---@generic T
---@param values {T} Values to search.
---@param predicate fun(value: T, index: number): boolean | promise<boolean> Predicate callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<T?> value First matching value, or nil when nothing matches.
function module.find<T>(
	values: {T},
	predicate: (value: T, index: number) -> (boolean | promiseModule.promise<boolean>),
	options: mapOptions?
): promiseModule.promise<T?>
	local matchesPromise = module.map(values, function(value: T, index: number)
		return predicate(value, index)
	end, options)

	return chain(matchesPromise, function(matches: {boolean}): T?
		for index, isMatch in matches do
			if not isMatch then continue end

			return values[index]
		end

		return nil
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Partitions values into matched and unmatched arrays using one predicate pass.
---@generic T
---@param values {T} Values to partition.
---@param predicate fun(value: T, index: number): boolean | promise<boolean> Predicate callback.
---@param options mapOptions? Optional concurrency limit.
---@return promise<partitionResult<T>> result Partitioned values in original input order.
function module.partition<T>(
	values: {T},
	predicate: (value: T, index: number) -> (boolean | promiseModule.promise<boolean>),
	options: mapOptions?
): promiseModule.promise<partitionResult<T>>
	local decisionsPromise = module.map(values, function(value: T, index: number)
		return chain(promiseModule.resolve(predicate(value, index)), function(include: boolean): filterDecision<T>
			return {
				include = include,
				value = value,
			}
		end)
	end, options)

	return chain(decisionsPromise, function(decisions: {filterDecision<T>}): partitionResult<T>
		local matched: {T} = {}
		local unmatched: {T} = {}

		for _, decision in decisions do
			if decision.include then
				matched[#matched + 1] = decision.value
				continue
			end

			unmatched[#unmatched + 1] = decision.value
		end

		return {
			matched = matched,
			unmatched = unmatched,
		}
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves keyed values without rejecting when an individual value rejects or is cancelled.
---@generic T
---@param values {[string]: T | promise<T>} Keyed values or Promily promises.
---@return promise<{[string]: settledResult<T>}> results Settlement result for every key.
function module.propsSettled<T>(
	values: {[string]: T | promiseModule.promise<T>}
): promiseModule.promise<{[string]: settledResult<T>}>
	local keys: {string} = {}

	for key in values do
		keys[#keys + 1] = key
	end

	if #keys == 0 then
		return promiseModule.resolve({})
	end

	return promiseModule.new(function(resolve, _reject, onCancel)
		local observers: {promiseModule.observer<any>} = {}
		local remaining = #keys
		local results: {[string]: settledResult<T>} = {}
		local stopped = false

		local function complete(key: string, resultValue: settledResult<T>)
			if stopped then return end

			results[key] = resultValue
			remaining -= 1

			if remaining > 0 then return end

			stopped = true
			disconnectObservers(observers)
			resolve(results)
		end

		onCancel(function(_reason)
			stopped = true
			disconnectObservers(observers)
		end)

		for _, key in keys do
			local source = promiseModule.resolve(values[key])

			local observerValue = source.observe(
				function(resolvedValue: T)
					complete(key, {
						reason = nil,
						status = "Resolved",
						value = resolvedValue,
					})
				end,
				function(reason: any)
					complete(key, {
						reason = reason,
						status = "Rejected",
						value = nil,
					})
				end,
				function(reason: any?)
					complete(key, {
						reason = reason,
						status = "Cancelled",
						value = nil,
					})
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Runs promise-producing tasks lazily until one resolves.
--- Unlike any(), later tasks are not started unless earlier tasks fail.
---@generic T
---@param tasks {fun(): T | promise<T>} Lazy promise-producing tasks.
---@return promise<T> value First successfully resolved task value.
function module.firstResolved<T>(
	tasks: {() -> (T | promiseModule.promise<T>)}
): promiseModule.promise<T>
	if #tasks == 0 then
		return promiseModule.reject(errors.aggregate({}))
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local activeObserver: promiseModule.observer<T>?
		local activePromise: promiseModule.promise<T>?
		local index = 0
		local reasons: {any} = table.create(#tasks)
		local stopped = false

		local runNext: () -> ()

		local function disconnectActive()
			if activeObserver then
				activeObserver.disconnect()
				activeObserver = nil
			end

			activePromise = nil
		end

		local function fail(reason: any)
			if stopped then return end

			reasons[index] = reason
			disconnectActive()

			if index >= #tasks then
				stopped = true
				reject(errors.aggregate(reasons))
				return
			end

			runNext()
		end

		runNext = function()
			if stopped then return end

			index += 1

			local taskCallback = tasks[index]
			local promiseValue = promiseModule.try(taskCallback)
			activePromise = promiseValue

			activeObserver = promiseValue.observe(
				function(value: T)
					if stopped then return end

					stopped = true
					disconnectActive()
					resolve(value)
				end,
				fail,
				function(reason: any?)
					fail(errors.cancelledInput(reason))
				end
			)
		end

		onCancel(function(reason)
			if stopped then return end

			stopped = true

			if activeObserver then
				activeObserver.disconnect()
				activeObserver = nil
			end

			if activePromise then
				activePromise.cancel(reason)
				activePromise = nil
			end
		end)

		runNext()
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Runs an asynchronous side effect for each value and returns the original values.
---@generic T
---@param values {T} Values to visit.
---@param callback fun(value: T, index: number): any | promiseModule.promise<any> Side-effect callback.
---@param options mapOptions? Optional concurrency limit.
---@return promiseModule.promise<{T}> promiseValue Original values after all callbacks finish.
function module.each<T>(
	values: {T},
	callback: (value: T, index: number) -> (any | promiseModule.promise<any>),
	options: mapOptions?
): promiseModule.promise<{T}>
	return module.map(values, function(value, index)
		return chain(promiseModule.resolve(callback(value, index)), function()
			return value
		end)
	end, options)
end

--————————————————————————————————————————————————————————————————————--

--- Runs lazy Promise-producing tasks sequentially.
---@generic R
---@param tasks {fun(): R | promiseModule.promise<R>} Lazy tasks to run in order.
---@return promiseModule.promise<{R}> promiseValue Results in task order.
function module.sequence<R>(
	tasks: {() -> (R | promiseModule.promise<R>)}
): promiseModule.promise<{R}>
	local taskIndexes: {number} = table.create(#tasks)

	for index = 1, #tasks do
		taskIndexes[index] = index
	end

	return module.map(taskIndexes, function(index)
		return tasks[index]()
	end, {
		concurrency = 1,
	})
end

--————————————————————————————————————————————————————————————————————--

--- Reduces values through a synchronous or asynchronous reducer.
---@generic T
---@generic R
---@param values {T} Values to reduce.
---@param reducer fun(accumulator: R, value: T, index: number): R | promiseModule.promise<R> Reducer callback.
---@param initialValue R Initial accumulator value.
---@return promiseModule.promise<R> promiseValue Final accumulator.
function module.reduce<T, R>(
	values: {T},
	reducer: (accumulator: R, value: T, index: number) -> (R | promiseModule.promise<R>),
	initialValue: R
): promiseModule.promise<R>
	local current = promiseModule.resolve(initialValue)

	for index, value in values do
		current = chain(current, function(accumulator: R)
			return reducer(accumulator, value, index)
		end)
	end

	return current
end

--————————————————————————————————————————————————————————————————————--

return module
