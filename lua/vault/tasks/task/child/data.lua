local error_formatter = require("vault.errors.formatter")
local TagDocumentation = require("vault.tags.tag.documentation")

--- @class vault.Tag.Child.Data: vault.Tag.Data
--- @field parent vault.Tag.Data.name
--- @field siblings vault.Tag.Data.name[]
local TagChildData = {}

--- @param parent vault.Tag.Data|vault.Tag.Child.Data
--- @param this table
--- @return vault.Tag.Child.Data
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
