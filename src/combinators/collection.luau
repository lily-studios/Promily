--!strict

-- implements Promily collection combinators without polling or permanent runtime loops

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
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

--————————————————————————————————————————————————————————————————————--

local function disconnectObservers(observers: {promiseModule.observer<any>})
	for _, observerValue in observers do
		observerValue.disconnect()
	end

	table.clear(observers)
end

--————————————————————————————————————————————————————————————————————--

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
			reject({
				kind = "CancelledInput",
				reason = reason,
			})
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
					reject({
						kind = "CancelledInput",
						reason = reason,
					})
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.any<T>(values: {T | promiseModule.promise<T>}): promiseModule.promise<T>
	if #values == 0 then
		return promiseModule.reject({
			kind = "AggregateError",
			reasons = {},
		})
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
			reject({
				kind = "AggregateError",
				reasons = reasons,
			})
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
					fail(index, {
						kind = "CancelledInput",
						reason = reason,
					})
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.some<T>(
	values: {T | promiseModule.promise<T>},
	count: number
): promiseModule.promise<{T}>
	assert(count >= 0, "Promily.some() count must be non-negative.")

	if count == 0 then
		return promiseModule.resolve({})
	end

	if count > #values then
		return promiseModule.reject({
			kind = "InsufficientInputs",
			requested = count,
			total = #values,
		})
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
			reject({
				kind = "AggregateError",
				reasons = failures,
			})
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
					fail({
						kind = "CancelledInput",
						reason = reason,
					})
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

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
					reject({
						kind = "CancelledInput",
						reason = reason,
					})
				end
			)

			observers[#observers + 1] = observerValue :: promiseModule.observer<any>
		end
	end)
end

--————————————————————————————————————————————————————————————————————--

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

	assert(concurrency >= 1, "Promily.map() concurrency must be at least 1.")

	concurrency = math.min(concurrency, total)

	return promiseModule.new(function(resolve, reject, onCancel)
		local active = 0
		local completed = 0
		local nextIndex = 1
		local observers: {promiseModule.observer<any>} = {}
		local results: {R} = table.create(total)
		local stopped = false

		local startNext: () -> ()

		local function stop(reason: any)
			if stopped then return end

			stopped = true
			disconnectObservers(observers)
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

				local observerValue = mappedPromise.observe(
					function(resolvedValue: R)
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
						stop(reason)
					end,
					function(reason: any?)
						stop({
							kind = "CancelledMapper",
							reason = reason,
						})
					end
				)

				observers[#observers + 1] = observerValue :: promiseModule.observer<any>
			end
		end

		onCancel(function(_reason)
			stopped = true
			disconnectObservers(observers)
		end)

		startNext()
	end)
end

--————————————————————————————————————————————————————————————————————--

function module.each<T>(
	values: {T},
	callback: (value: T, index: number) -> (any | promiseModule.promise<any>),
	options: mapOptions?
): promiseModule.promise<{T}>
	return module.map(values, function(value, index)
		return promiseModule.resolve(callback(value, index)).andThen(function()
			return value
		end)
	end, options)
end

--————————————————————————————————————————————————————————————————————--

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

function module.reduce<T, R>(
	values: {T},
	reducer: (accumulator: R, value: T, index: number) -> (R | promiseModule.promise<R>),
	initialValue: R
): promiseModule.promise<R>
	local current = promiseModule.resolve(initialValue)

	for index, value in values do
		current = current.andThen(function(accumulator: R)
			return reducer(accumulator, value, index)
		end)
	end

	return current
end

--————————————————————————————————————————————————————————————————————--

return module
