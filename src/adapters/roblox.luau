--!strict

-- adapts Roblox signals, properties, attributes, and hierarchy changes into Promily promises

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type eventOptions = {
	predicate: ((...any) -> boolean)?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}

export type valueOptions<T> = {
	predicate: ((value: T) -> boolean)?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}

export type childOptions = {
	className: string?,
	recursive: boolean?,
	timeoutReason: any?,
	timeoutSeconds: number?,
}

--————————————————————————————————————————————————————————————————————--

local function createTimeout(
	seconds: number?,
	reason: any?,
	onTimeout: (reason: any) -> ()
): thread?
	if seconds == nil then return nil end

	assert(
		seconds == seconds and seconds < math.huge and seconds >= 0,
		"Promily adapter timeout must be finite and non-negative."
	)

	local timeoutReason = reason

	if timeoutReason == nil then
		timeoutReason = `Promily adapter timed out after {seconds} seconds.`
	end

	return task.delay(seconds, onTimeout, timeoutReason)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves from the next Roblox signal emission that satisfies the configured filter.
---@param signal RBXScriptSignal Roblox signal to observe.
---@param options eventOptions? Optional filtering and timeout behavior.
---@return promiseModule.promise<{any}> promiseValue Promise containing packed signal arguments.
function module.fromEvent(
	signal: RBXScriptSignal,
	options: eventOptions?
): promiseModule.promise<{any}>
	return promiseModule.new(function(resolve, reject, onCancel)
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function onSignal(...: any)
			if settled then return end

			if options and options.predicate then
				local success, accepted = pcall(options.predicate :: any, ...)

				if not success then
					settled = true
					cleanup()
					reject(accepted)
					return
				end

				if not accepted then return end
			end

			settled = true
			cleanup()
			resolve(table.pack(...))
		end

		connection = signal:Connect(onSignal)

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			if settled then return end

			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when a Roblox property satisfies the configured target value or predicate.
---@generic T
---@param instance Instance Instance containing the property.
---@param propertyName string Property name to observe.
---@param options valueOptions<T>? Optional predicate, target value, and timeout behavior.
---@return promiseModule.promise<T> promiseValue Promise containing the matching property value.
function module.fromProperty<T>(
	instance: Instance,
	propertyName: string,
	options: valueOptions<T>?
): promiseModule.promise<T>
	assert(propertyName ~= "", "Promily.fromProperty() propertyName cannot be empty.")

	return promiseModule.new(function(resolve, reject, onCancel)
		local target = instance :: any
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function testCurrent(): boolean
			if settled then return true end

			local readSuccess, readValue = pcall(function()
				return target[propertyName]
			end)

			if not readSuccess then
				settled = true
				cleanup()
				reject(readValue)
				return true
			end

			local value = readValue :: T

			if options and options.predicate then
				local success, accepted = pcall(options.predicate, value)

				if not success then
					settled = true
					cleanup()
					reject(accepted)
					return true
				end

				if not accepted then return false end
			end

			settled = true
			cleanup()
			resolve(value)

			return true
		end

		local signalSuccess, signalValue = pcall(function()
			return instance:GetPropertyChangedSignal(propertyName)
		end)

		if not signalSuccess then
			settled = true
			reject(signalValue)
			return
		end

		connection = (signalValue :: RBXScriptSignal):Connect(function()
			if settled then return end

			testCurrent()
		end)

		if testCurrent() then return end

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			if settled then return end

			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when a Roblox attribute satisfies the configured target value or predicate.
---@generic T
---@param instance Instance Instance containing the attribute.
---@param attributeName string Attribute name to observe.
---@param options valueOptions<T>? Optional predicate, target value, and timeout behavior.
---@return promiseModule.promise<T> promiseValue Promise containing the matching attribute value.
function module.fromAttribute<T>(
	instance: Instance,
	attributeName: string,
	options: valueOptions<T>?
): promiseModule.promise<T>
	assert(attributeName ~= "", "Promily.fromAttribute() attributeName cannot be empty.")

	return promiseModule.new(function(resolve, reject, onCancel)
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function testCurrent(): boolean
			if settled then return true end

			local currentValue = instance:GetAttribute(attributeName)
			if currentValue == nil then return false end

			local value = currentValue :: T

			if options and options.predicate then
				local success, accepted = pcall(options.predicate, value)

				if not success then
					settled = true
					cleanup()
					reject(accepted)
					return true
				end

				if not accepted then return false end
			end

			settled = true
			cleanup()
			resolve(value)

			return true
		end

		connection = instance:GetAttributeChangedSignal(attributeName):Connect(function()
			if settled then return end

			testCurrent()
		end)

		if testCurrent() then return end

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			if settled then return end

			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

--- Resolves when a matching child exists below the requested parent.
---@param parent Instance Parent instance to observe.
---@param name string Required child name.
---@param options childOptions? Optional class, recursive-search, and timeout behavior.
---@return promiseModule.promise<Instance> promiseValue Promise containing the matching child.
function module.fromChild(
	parent: Instance,
	name: string,
	options: childOptions?
): promiseModule.promise<Instance>
	assert(name ~= "", "Promily.fromChild() name cannot be empty.")

	local recursive = false
	local className: string? = nil

	if options then
		recursive = options.recursive == true
		className = options.className
	end

	return promiseModule.new(function(resolve, reject, onCancel)
		local connection: RBXScriptConnection?
		local timerThread: thread?
		local settled = false

		local function cleanup()
			local currentConnection = connection
			connection = nil

			if currentConnection then
				currentConnection:Disconnect()
			end

			if not timerThread then return end

			task.cancel(timerThread)
			timerThread = nil
		end

		local function matches(instance: Instance): boolean
			if instance.Name ~= name then return false end
			if className and not instance:IsA(className) then return false end

			return true
		end

		local function resolveIfMatch(instance: Instance): boolean
			if settled then return true end
			if not matches(instance) then return false end

			settled = true
			cleanup()
			resolve(instance)

			return true
		end

		local signal = parent.ChildAdded

		if recursive then
			signal = parent.DescendantAdded
		end

		connection = signal:Connect(function(instance)
			if settled then return end

			resolveIfMatch(instance)
		end)

		local existingObjects = parent:GetChildren()

		if recursive then
			existingObjects = parent:GetDescendants()
		end

		for _, instance in existingObjects do
			if not resolveIfMatch(instance) then continue end

			return
		end

		if options then
			timerThread = createTimeout(
				options.timeoutSeconds,
				options.timeoutReason,
				function(reason)
					if settled then return end

					settled = true
					cleanup()
					reject(reason)
				end
			)
		end

		onCancel(function(_reason)
			if settled then return end

			settled = true
			cleanup()
		end)
	end)
end

--————————————————————————————————————————————————————————————————————--

return module
