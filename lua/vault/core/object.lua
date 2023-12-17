-- source: https://github.com/kikito/middleclass
-- source: https://github.com/MunifTanjim/nui.nvim

---@class VaultObject
---@field class VaultClass -- Represents the class of the object.
---@field static table -- Holds the static (shared) properties/methods of the class.
---@field name string -- The name of the class.
---@field super VaultClass? -- Represents the super class of the object.
---@field __meta table -- Metatable for instances of the class.
---@field __properties table -- Stores instance properties.
---@field __index fun(self: table, key: string): any -- Handles property access for instances of the class.
---@field __newindex fun(self: table, key: string, value: any): nil -- Handles property assignment for instances of the class.
---@field __tostring fun(self: table): string -- Handles conversion to string for instances of the class (e.g. when using tostring(instance)).
---@field __call fun(self: table, ...): table -- Allows instances of the class to be called as functions (e.g. Foo()).
---@field init fun(self: table, ...): nil -- The constructor of the class.
---@field new fun(self: table, ...): table -- Creates a new instance of the class.
---@field extend fun(self: table, name: string): VaultObject -- Extends the class with a new subclass.
---@field is_subclass_of fun(self: table, class: VaultClass): boolean -- Checks if the class is a subclass of another class.
---@field is_instance_of fun(self: table, class: VaultClass): boolean -- Checks if the class is an instance of another class.

---@class VaultClass: VaultObject

---@class VaultSubClass: VaultClass
---@field super VaultClass

local idx = {
    subclasses = { "<vault.utils.object:subclasses>" },
}

---@return string
local function __tostring(self)
    return "class " .. self.name
end

---@param self VaultClass|VaultSubClass
---@return VaultClass
local function __call(self, ...)
    return self:new(...)
end

---@param class VaultClass|VaultSubClass
---@param index table|function
---@return table|function
local function create_index_wrapper(class, index)
    if type(index) == "table" then
        return function(self, key)
            local value = self.class.__meta[key]
            if value == nil then
                return index[key]
            end
            return value
        end
    elseif type(index) == "function" then
        return function(self, key)
            local value = self.class.__meta[key]
            if value == nil then
                return index(self, key)
            end
            return value
        end
    else
        return class.__meta
    end
end

---@param class VaultClass|VaultSubClass
---@param key string - property name
---@return nil
local function propagate_instance_property(class, key, value)
    value = key == "__index" and create_index_wrapper(class, value) or value

    class.__meta[key] = value

    for subclass in pairs(class[idx.subclasses]) do
        if subclass.__properties[key] == nil then
            propagate_instance_property(subclass, key, value)
        end
    end
end

---@param class VaultClass|VaultSubClass
---@param key string - property name
---@param value any - property value
---@return nil
local function declare_instance_property(class, key, value)
    class.__properties[key] = value

    if value == nil and class.super then
        value = class.super.__meta[key]
    end

    propagate_instance_property(class, key, value)
end

--- Check if subclass is `VaultSubClass` of `VaultClass`
---
---@param subclass VaultClass|VaultSubClass - subclass to check
---@param class VaultClass|VaultSubClass - class to check
---@return boolean - is subclass of class or not
local function is_subclass(subclass, class)
    if not subclass.super then
        return false
    end
    if subclass.super == class then
        return true
    end
    return is_subclass(subclass.super, class)
end

--- Check if instance is `VaultClass` or `VaultSubClass` of `VaultClass`
---
---@param instance VaultObject - instance to check
---@param class VaultClass|VaultSubClass - class to check
---@return boolean - is instance of class or not
local function is_instance(instance, class)
    if instance.class == class then
        return true
    end
    return is_subclass(instance.class, class)
end

--- Create `VaultClass` or `VaultSubClass`
---
---@param name string - name of the class
---@param super VaultClass|VaultSubClass? - super class
---@return VaultClass|VaultSubClass
local function create_class(name, super)
    assert(name, "missing name")

    local meta = {
        is_instance_of = is_instance,
    }
    meta.__index = meta

    local class = {
        super = super,
        name = name,
        static = {
            is_subclass_of = is_subclass,
        },

        [idx.subclasses] = setmetatable({}, { __mode = "k" }),

        __meta = meta,
        __properties = {},
    }

    setmetatable(class.static, {
        __index = function(_, key)
            local value = rawget(class.__meta, key)
            if value == nil and super then
                return super.static[key]
            end
            return value
        end,
    })

    setmetatable(class, {
        __call = __call,
        __index = class.static,
        __name = class.name,
        __newindex = declare_instance_property,
        __tostring = __tostring,
    })

    return class
end

--- Create `VaultObject`
---
---@param name string
---@return VaultObject
local function create_object(_, name)
    ---@type VaultClass
    local Class = create_class(name)

    ---@return string
    function Class:__tostring()
        return "instance of " .. tostring(self.class)
    end

    ---@return nil
    function Class:init() end -- luacheck: no unused args

    function Class.static:new(...)
        local instance = setmetatable({ class = self }, self.__meta)
        instance:init(...)
        return instance
    end

    --- Extend `VaultClass` or `VaultSubClass`
    ---
    ---@param subclass_name string
    ---@return VaultSubClass
    function Class.static:extend(subclass_name) -- luacheck: no redefined
        ---@type VaultSubClass|VaultClass
        local subclass = create_class(subclass_name, self)

        for key, value in pairs(self.__meta) do
            if not (key == "__index" and type(value) == "table") then
                propagate_instance_property(subclass, key, value)
            end
        end

        ---@return nil
        function subclass.init(instance, ...)
            self.init(instance, ...)
        end

        self[idx.subclasses][subclass] = true

        ---@cast subclass -VaultClass
        return subclass
    end

    ---@type VaultObject
    return Class
end

--luacheck: push no max line length

--- Create `VaultObject`
---
---@type (fun(name: string): VaultObject)|{ is_subclass: (fun(subclass: VaultObject, class: VaultObject): boolean), is_instance: (fun(instance: VaultObject, class: VaultObject): boolean) }
local VaultObject = setmetatable({
    is_subclass = is_subclass,
    is_instance = is_instance,
}, {
    __call = create_object,
})

---@class VaultInstance - Represents an instance of a class. Instances of this class can be created by calling the class itself (e.g. Foo()).
---@field class VaultClass -- Represents the class of the object.
---@field __index fun(self: table, key: string): any -- Handles property access for instances of the class.
---@field __tostring fun(self: table): string -- Handles conversion to string for instances of the class (e.g. when using tostring(<VaultInstance>)).
---@field init fun(self: table, ...): nil -- The constructor of the class. Override this method to add your own initialization logic.
---@field is_instance_of fun(self: table, class: VaultClass): boolean -- Checks if the class is an instance of another class.

return VaultObject
