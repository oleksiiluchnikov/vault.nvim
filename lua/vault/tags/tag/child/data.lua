local error_formatter = require("vault.errors.formatter")
local TagDocumentation = require("vault.tags.tag.documentation")

---@class VaultTagChild.data: VaultTag.data
---@field parent VaultTag.data.name
---@field siblings VaultTag.data.name[]
local TagChildData = {}

---@param parent VaultTag.data|VaultTagChild.data
---@param this table
---@return VaultTagChild.data
function TagChildData:new(parent, this)
    if not parent then
        error(error_formatter.missing_parameter("parent"), 2)
    end
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    if type(this) == "string" then
        this = { name = this }
    end
    if not this.name then
        error(error_formatter.missing_parameter("name"), 2)
    end

    this.root = this.root or parent.root or parent.name
    if not this.root then
        error(error_formatter.missing_parameter("root"), 2)
    end

    this.siblings = this.siblings or vim.tbl_keys(parent.children)
    this.documentation = TagDocumentation(this.name)

    self = vim.tbl_deep_extend("force", this, self)
    return self
end

return TagChildData
