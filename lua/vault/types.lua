
---@class vault
local vault = {}



-- local Classes = {
--   ---@class Inbox
--   Inbox = Inbox,
--   Zettel = {
--     description = "A note that contains some information.",
--     dir = "Notes",
--     emoji = "📝",
--   },
--
--   View = {
--     description = "A note that contains a view of some information.",
--     dir = "View",
--     emoji = "👀",
--   },
--
--   Value = {
--     description = "A not that contains a core life value.",
--     dir = "Value",
--     -- emoji artist palette
--     emoji = "🎨",
--   },
--
--   Aspiration = {
--     description = "A note that contains a core life aspiration.",
--     dir = "Aspiration",
--     emoji = "🌈",
--   },
--
--   Path = {
--     description = "A note that contains a path to achieve an aspiration.",
--     dir = "Path",
--     emoji = "🛣️",
--   },
--
--   Habit = {
--     description = "A note that contains a habit to achieve a path.",
--     dir = "Habit",
--     emoji = "🧘",
--   },
--
--   Practice = {
--     description = "A note that contains a practice to achieve a habit.",
--     dir = "Practice",
--     emoji = "🏋️",
--   },
--
--   Goal = {
--     description = "It is something that have defined and measurable outcome.",
--     dir = "Goal",
--     emoji = "🏆",
--     status = {
--       "ACTIVE",
--       "COMPLETED",
--       "ARCHIVED",
--       "FAILED",
--     },
--   },
--
--   Project = {
--     description = "A project that requires multiple tasks to be completed.",
--     dir = "Project",
--     emoji = "📦",
--     status = {
--       "TODO",
--       "IN-PROGRESS",
--       "ON-HOLD",
--       "IN-REVIEW",
--       "DONE",
--       "DEPRECATED",
--     },
--   },
--
--   Task = {
--     description = "A task that requires some thought and planning.",
--     dir = "Task",
--     emoji = "📋",
--     status = {
--       "TODO",
--       "IN-PROGRESS",
--       "ON-HOLD",
--       "IN-REVIEW",
--       "DONE",
--       "DEPRECATED",
--     },
--   },
--
--   Routine = {
--     description = "A routine that is repeated daily.",
--     dir = "Routine",
--     emoji = "📅",
--     status = {
--       -- What is the status of a routine?
--     },
--   },
--
--   Action = {
--     description = "A small task that can be completed without any thought.",
--     dir = "Action",
--     emoji = "🔨",
--     status = {
--       "TODO",
--       "IN-PROGRESS",
--       "DONE",
--       "DEPRECATED",
--       "ON-HOLD",
--     },
--   },
--
--   Intention = {
--     description = "Is a desire to do something.",
--     dir = "Intention",
--     emoji = "🌱",
--   },
--
--   Idea = {
--     description = "Is a thought or suggestion as to a possible course of action.",
--     dir = "Idea",
--     emoji = "💡",
--   },
--
--   ["Awesome-List"] = {
--     description = "Is a curated list of awesome things.",
--     dir = "Awesome-List",
--     emoji = "📜",
--   },
--
--   Course = {
--     description = "Is a course that I am taking.",
--     dir = "Course",
--     emoji = "📚",
--     status = {
--       "TODO",
--       "IN-PROGRESS",
--       "DONE",
--       "DEPRECATED",
--       "ON-HOLD",
--     },
--   },
--
--   Event = {
--     description = "Is an event that I am attending.",
--     dir = "Event",
--     emoji = "📅",
--   },
--
--   Location = {
--     description = "Here some thougt about a location.",
--     dir = "Location",
--     emoji = "📍",
--   },
--
--   Meeting = {
--     description = "Is a meeting that I am attending.",
--     dir = "Meeting",
--     emoji = "💬",
--   },
--
--   Meta = {
--     description = "Is a note that contains some meta information about the vault.",
--     dir = "Meta",
--     emoji = "📝",
--   },
--
--   Paper = {
--     description = "Is a note like CV, Resume, Cover Letter, etc.",
--     dir = "Paper",
--     emoji = "📄",
--   },
--
--   Person = {
--     description = "Is a note about a person.",
--     dir = "Person",
--     emoji = "👤",
--   },
--
--   Property = {
--     description = "Is a note about a stuff that I own.",
--     dir = "Property",
--     emoji = "🏠",
--   },
--
--   Resource = {
--     description = "Is a resources like Prompt, Snippets, Templates, etc.",
--     dir = "Resource",
--     emoji = "📚",
--   },
--
--   Software = {
--     description = "Is a note about a software.",
--     dir = "Software",
--     emoji = "💻",
--   },
--
--   Journal = {
--     description = "It is a journaling note.",
--     dir = "Journal",
--     subdirs = {
--       "Daily",
--       "Weekly",
--       "Monthly",
--       "Yearly",
--     },
--     emoji = "📓",
--   },
-- }
--

local M = {}
---@class NoteClass
---@field description string
---@field dir string?
---@field emoji string
---@field tags string[]
function M.NoteClass.new()
	return {
		description = "",
		emoji = "",
		tags = {},
	}
end

---@class Inbox: NoteClass
---@field subdirs string[]
---@field status string[]
function M.Inbox.new()
	return {
		emoji = "📥",
		subdirs = {},
		status = {},
		tags = {},
	}
end

---@class Zettel: NoteClass
function M.Zettel.new()
	return {
		emoji = "📝",
		tags = {},
		dir = "Notes",
	}
end

---@class View: NoteClass
---@field subdirs string[]
function M.View.new()
	return {
		subdirs = {},
		tags = {},
	}
end

---@class Value: NoteClass
function M.Value.new()
	return {
		tags = {},
	}
end

---@class Aspiration: NoteClass
function M.Aspiration.new()
	return {
		tags = {},
	}
end

---@class Path: NoteClass
function M.Path.new()
	return {
		tags = {},
	}
end

---@class Habit: NoteClass
function M.Habit.new()
	return {
		tags = {},
	}
end

---@class Practice: NoteClass
function M.Practice.new()
	return {
		tags = {},
	}
end

---@class Goal: NoteClass
---@field status string[] - Possible status values for goals.
function M.Goal.new()
	return {
		status = {
			"ACTIVE",
			"COMPLETED",
			"ARCHIVED",
			"FAILED",
		},
	}
end

---@class Project: NoteClass
---@field status string[] - Possible status values for projects.
function M.Project.new()
	return {
		status = {
			"TODO",
			"IN-PROGRESS",
			"ON-HOLD",
			"IN-REVIEW",
			"DONE",
			"DEPRECATED",
		},
	}
end

---@class Task: NoteClass
---@field status string[] - Possible status values for tasks.
function M.Task.new()
	return {
		status = {
			"TODO",
			"IN-PROGRESS",
			"ON-HOLD",
			"IN-REVIEW",
			"DONE",
			"DEPRECATED",
		},
	}
end

---@class Routine: NoteClass
---@field status string[] - Possible status values for routines.
function M.Routine.new()
	return {
		status = {},
	}
end

---@class Action: NoteClass
---@field status string[] - Possible status values for actions.
function M.Action.new()
	return {
		status = {
			"TODO",
			"DONE",
		},
	}
end

---@class Intention: NoteClass
function M.Intention.new()
	return {}
end

---@class Idea: NoteClass
function M.Idea.new()
	return {}
end

---@class AwesomeList: NoteClass
function M.AwesomeList.new()
	return {}
end

---@class Course: NoteClass
---@field status string[] - Possible status values for courses.
function M.Course.new()
	return {
		status = {},
	}
end

---@class Event: NoteClass
function M.Event.new()
	return {}
end

---@class Location: NoteClass
function M.Location.new()
	return {}
end

---@class Meeting: NoteClass
function M.Meeting.new()
	return {}
end

---@class Meta: NoteClass
function M.Meta.new()
	return {}
end

---@class Paper: NoteClass
function M.Paper.new()
	return {}
end

---@class Person: NoteClass
function M.Person.new()
	return {}
end

---@class Property: NoteClass
function M.Property.new()
	return {}
end

---@class Resource: NoteClass
function M.Resource.new()
	return {}
end

---@class Software: NoteClass
function M.Software.new()
	return {}
end

---@class Journal: NoteClass
---@field subdirs string[] - Subdirectories within the journal class.
function M.Journal.new()
	return {
		subdirs = {
			"Daily",
			"Weekly",
			"Monthly",
			"Yearly",
		},
	}
end

---@class DailyJournal: Journal
function M.DailyJournal.new()
	return {}
end

---@class WeeklyJournal: Journal
function M.WeeklyJournal.new()
	return {}
end

---@class MonthlyJournal: Journal
function M.MonthlyJournal.new()
	return {}
end

---@class YearlyJournal: Journal
function M.YearlyJournal.new()
	return {}
end

---@class Frontmatter: Note
---@field uuid string
---@field date-created string
---@field date-modified string
---@field shared boolean
function M.Frontmatter.new()
	return {
		uuid = "",
		["date-created"] = "",
		["date-modified"] = "",
		shared = false,
	}
end
