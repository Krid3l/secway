# secway
Stupid but Employable CSV Wrangler, Editor and Yanker.

Made for Devos Code's September 2022 contest.

## Compilation
The project can be compiled with `dub build` once you've installed the [DMD toolchain](https://dlang.org/download.html).

## Usage
The executable is meant to be run from the command line.

It takes a maximum of three arguments:

### Argument 1: The actual filename
Example usage: `chocolates.csv`

Secway refuses any filename without a .csv extension, and will check for the integrity of the file's structure.

### Argument 2: The initial task (default: `f`)
Example usage: `--task r`

See below for a list of tasks, with their purposes and their aliases.

If no task argument is provided, Secway will simply revert to free mode and ask the user (via stdin) for a task to perform.

### Argument 3: The header confirmation (default: `n`)
Only accepts `yes`, `no` or one of their aliases.

Example usage: `--header yeah`

Due to the freeform nature of the data stored in a CSV file, Secway has no automatic mechanism to detect header rows.

This argument allows you to confirm if there's indeed a header row in the provided CSV file.

Aliases for `yes`: `"y", "true", "yeah", "aye", "oui"`

Aliases for `no`: `"n", "false", "nope", "nah", "non"`

### Example command using all arguments
`<executable name> comrades.csv --task d --header y`

## Tasks
The task provided as a command line argument is only the first to be carried out.

After a task is done, Secway gives you the option to start another one.

Secway does *not* output any file until the `save` task is triggered by the user. Instead, Secway edits the data in a buffer until a save is prompted. The buffer gets assigned with the provided file's contents after the structure of these contents has been validated.

There is currently no way for Secway to revert an edit done to the data stored inside the buffer.

### Free
Secway's default mode. Triggers a prompt for the next task to perform.

### Create
Allows to add a row or column to the file buffer.

At this time, `create` can only append. Secway is not yet capable of inserting new rows or columns between existing ones.

### Read
Displays the contents of a cell or row without altering any data in the file buffer.

### Update
Changes the contents of a cell or row. Also executes the `read` task to print the selected data to stdout before any change is applied.

### Delete
Deletes one row or column.

Confirmation asked after data selection.

The header row cannot be deleted.

If a row is about to be pruned, also executes the `read` task to print the row's data to stdout before any change is applied.

### Save
Outputs a file containing the data inside Secway's buffer.

The output file's name can have an extension other than .csv, or be bereft of any.

If the default options are selected during the successive prompts, the output file's name will be a merge of the original file's name, followed by a UNIX timestamp, ending with .csv.

### Help
Prints a shorter version of the present section to stdout.

### Quit
Exits Secway. Will ask for confirmation if unsaved changes are detected.

### Task aliases
```
"free":     "freemode", "f", "normal", "?"
"create":   "create", "c", "insert", "append", "yank"
"read":     "read", "r", "retrieve", "see", "list", "value", "whatis"
"update":   "update", "u", "replace", "change"
"delete":   "delete", "d", "suppress", "nuke", "prune"
"save":     "save", "s", "write"
"help":     "help", "h", "tasks", "wtf"
"quit":     "quit", "q", "exit", "terminate", "bye"
```

## Known bugs
Using `delete` to suppress a column throws an error: `range is smaller than amount of items to pop`. This will be fixed in the next commit.
