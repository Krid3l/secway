/* Secwey - Stupid but Employable CSV Wrangler, Editor and Yanker
 * MIT licence
 * Made by Kridel (kridel.me)
 * - = - = - = -
 * Written for Devos Code's september 2022 CSV parser contest
 * Maybe I'll do something more with this later?...
 *
 * >>> Contest rules:
 * > No usage of pre-made CSV-parsing code
 * 	 (whether it's from the language's stdlib or from a 3rd party source / lib)
 * > The software must be able to alter the file's cells, header cells included
 * > The software must be able to delete individual rows, header row excluded
 *
 * >>> Contest bonuses:
 * > Column deletion
 * > Functions computing results from cells, rows or columns
 * > Line formatting (e.g. reorganizing data with a model taken from the header
	 or from another line in the file)
 *
 * >>> My design goals:
 * > Single-file, less than 1k SLOC
 * > Compromise between code clarity and performance
 * > Use nothing but Dlang's stdlib (exclusing std.csv as per contest rules)
 */

module secwey;

import
    std.file,
    std.conv,
    std.stdio,
    std.regex,
    std.getopt,
    std.algorithm,
    core.stdc.stdlib; // for exit()

static import
    std.string, // to avoid confusion with std.algorithm's strip()
    std.ascii;

struct FileHandler {
    // [row][cell]
    string[][] fileContents;

    // That member function is a tad long. I should delocalize pieces of it at
    //  program scope; that would allow to better track the control flow too.
    void parseContents(ref FileInfo loadedFileInfo) {
        string csvFileTokens;
        string buf_cell = "";
        auto fileToDissect = File(loadedFileInfo.filename, "r");
        auto lineRange = fileToDissect.byLine();
        uint lineNumber = 0;
        ulong primalCellCount = 0;
        // ___ File layer ___
        foreach (line; lineRange) {
            // ___ Line layer ___         
            // Only validated rows are counted.
            // This also prevents adding empty rows just behind EOF to the
            //  file count.
            lineNumber = loadedFileInfo.rowCount;
            if (line == "") {
                writeln("[INFO] Line " ~ to!string(lineNumber + 1) ~ " is empty. Skipping...");
                continue;
            }
            else {
                // Extending the dynamic 2d array for proper later access
                fileContents.length++;
            }
            
            auto cellsFromRow = std.string.split(line, ",");
            if (primalCellCount <= 0) {
                primalCellCount = cellsFromRow.length;
            } else if (primalCellCount != cellsFromRow.length) {
                // IETF RFC 4180 compliance
                writeln("[ERROR] The provided CSV file does not have the same number of cells on every row.\n"
                    ~ "        Line " ~ to!string(loadedFileInfo.rowCount + 1)
                    ~ " has " ~ to!string(cellsFromRow.length)
                    ~ " cells, comapred to the previously-detected count of " ~ to!string(primalCellCount)
                    ~ " per row.\nExiting..."
                );
                exit(1);
            }
            // Sweep the row's cells into the newly-created 2nd-level array slot
            foreach (cellIndex, cellContent; cellsFromRow) {
                fileContents[lineNumber] ~= to!string(cellContent);
                loadedFileInfo.cellCount++;
                loadedFileInfo.charCount += cellContent.length;
            }
            loadedFileInfo.rowCount++;
        }
    }
}

struct FileInfo {
    string filename     = "";
    int cellCount       = 0;
    int rowCount        = 0;
    int charCount       = 0;
    bool headerInFile   = false;
}

// Validates arguments provided on program execution
void validateArgs(string[] args, ref FileInfo loadedFileInfo, ref string task) {
    auto possibleTasks = [
        // Nope. Not yet. Maybe I'll do this later.
        // "free":  ["free", "freemode", "f", "normal", "?"],
        "create":   ["create", "c", "insert", "append", "yank"],
        "read":     ["read", "r", "retrieve", "see", "value", "what", "whatis"],
        "update":   ["update", "u", "replace", "change"],
        "delete":   ["delete", "d", "suppress", "nuke", "prune"]
    ];

    auto headerArgValues = [
        "yes":  ["yes", "y", "true", "yeah", "aye", "oui"],
        "no":   ["no", "n", "false", "nope", "nah", "non"]
    ];

    auto csvFileRegex = (r"^.*\.(csv)");
    auto csvFileMatchArray = matchFirst(args[1], csvFileRegex);
    string headerArg = "";

    if (csvFileMatchArray.empty) {
        writeln("[ERROR] No CSV filename provided. Exiting...");
        exit(1);
    } else {
        string filenameArg = csvFileMatchArray[0];
        if (!filenameArg.exists()) {
            writeln("[ERROR] Cannot find " ~ filenameArg ~ ". Exiting...");
            exit(1);
        }
        loadedFileInfo.filename = filenameArg;
    }

    // Fetches the operation that the user desires to perform on the filename
    // Since expliciting a flag ousts the argument from the args array, it is
    //  directly assigned to the referenced strings instead
    getopt(
        args,
        "task", &task,
        "header", &headerArg
    );
    
    bool taskIsValid = false;
    foreach (taskAliasCur, taskAliasGroup; possibleTasks) {
        if (taskAliasGroup.canFind(task)) {
            taskIsValid = true;
            // Transform the alias into the proper internal task name
            task = taskAliasCur;
            break;
        }
    }

    if (!taskIsValid) {
        writeln("[WARN] Provided task argument is "
            ~ (task == "" ? "empty" : "invalid") ~ "." 
            ~ "\n>>>>>> Reverting secway to read mode."
        );
        task = "read";
    }

    if (headerArg == "") {
        writeln("[INFO] No header argument provided."
            ~ "\n>>>>>> Secway will assume there's no header in the file."
        );
    } else if (headerArgValues["yes"].canFind(headerArg)) {
        loadedFileInfo.headerInFile = true;
    } else {
        if (!headerArgValues["no"].canFind(headerArg)) {
            writeln("[WARN] The provided header argument is invalid."
                ~ "\n>>>>>> Secway will assume there's no header in the file."
            );
        }
    }
}

// Ensure that the file is a valid CSV file as per the IETF RFC 4180 standard
void validateFile(ref FileInfo loadedFileInfo, ref FileHandler fileHandler) {
    // Deliberately, I won't pass a file pointer throught the whole of Secway.
    // Instead, I'm just going to open and close the CSV file only when
    //  operations ought to be performed. (e.g. in FileHandler.parseContents())
    fileHandler.parseContents(loadedFileInfo);

    writeln("\n  Info about " ~ loadedFileInfo.filename ~ ":\n"
        ~ "\n* Character count (excluding separators and CL/RFs)\n  " ~ to!string(loadedFileInfo.charCount)
        ~ "\n* Cell count\n  " ~ to!string(loadedFileInfo.cellCount)
        ~ "\n* Row count\n  " ~ to!string(loadedFileInfo.rowCount)
        ~ "\n* Header row? (user-specified)\n  " ~ (loadedFileInfo.headerInFile ? "yes" : "no")
    );
}

// Integer helper: When you need a helping hand!
// Be careful to feed the input stripped of CR/LFs
string isUserInputNumeric(char[] input) {
    if (std.string.isNumeric(to!string(input))) {
        int numInput = to!int(input);
        writeln(numInput);
        if (numInput < 0) {
            return "NEG";
        } else if (numInput == 0) {
            return "ZERO";
        } else {
            return "POS";
        }
    } else {
        return "NONE";
    }
}

// Does not exit until the user feeds a non-negative integer to stdin
ulong forceUintInput(bool zeroAllowed = false) {
    char[] buf;
    bool firstTry = true;
    string inputType;

    // TODO: Hmmmmm yes, delicious redundency. Shorten that ASAP.
    if (zeroAllowed) {
        while (inputType != "POS" && inputType != "ZERO") {
            if (!firstTry)
                write("\nPlease input zero or a positive integer.\n> ");
            readln(buf);
            buf = std.string.chomp(buf); // pruning CR/LFs from the user input
            inputType = isUserInputNumeric(buf);
            firstTry = false;
        }
    } else {
        while (inputType != "POS") {
            if (!firstTry)
                write("\nPlease input a positive and non-zero integer.\n> ");
            readln(buf);
            buf = std.string.chomp(buf); // pruning CR/LFs from the user input
            inputType = isUserInputNumeric(buf);
            firstTry = false;
        }
    }

    return to!ulong(buf);
}

void read(ref FileInfo loadedFileInfo, ref FileHandler fileHandler) {
    // TODO: Allow the user to enter keywords instead of numbers, such as
    //  "first", "last", etc
    // I can sense the sweet, harrowing presence of feature creep getting closer
    ulong rowId, cellId = 0;
    string[] rowToRead = [];

    write("Please enter the row number to look up.\n> ");
    RowIdInput:
    rowId = forceUintInput();

    if (rowId > fileHandler.fileContents.length) {
        writeln("[WARN] The row number you provided exceeds the actual number of rows in the file."
            ~ "\n       Please input a valid row number.\n> "
        );
        goto RowIdInput;
    } else {
        rowToRead = fileHandler.fileContents[rowId - 1];
    }

    write("\nPlease enter the cell position to look up.\n"
        ~ "Enter zero to display the whole row.\n> "
    );
    CellIdInput:
    cellId = forceUintInput(true);

    if (cellId > fileHandler.fileContents[rowId - 1].length) {
        write("[WARN] The cell number you provided exceeds the actual number of cells in the row you selected."
            ~ "\n       Please input a valid cell number.\n> "
        );
        goto CellIdInput;
    }

    
    if (cellId == 0) {
        ulong cellCount = 0;
        foreach (cellContents; rowToRead) {
            cellCount++;
            write(std.string.strip(cellContents)
                ~ (cellCount >= rowToRead.length ? "\n" : ",")
            );
        }
    } else {
        writeln(std.string.strip(rowToRead[cellId - 1]));
    }
}

void performTask(string task, ref FileInfo loadedFileInfo, ref FileHandler fileHandler) {
    // TODO: Allow user to follow up with another task after one is done
    writeln("\nOperation selected: " ~ std.string.capitalize(task) ~ ".");

    switch (task) {
        // -=-=- For rows -=-=-
        case "create":
            goto default;
        case "delete":
            goto default;
        // -=-=- For cells -=-=-
        case "update":
            goto default;
        // -=-=- For both rows and cells -=-=-
        case "read":
            read(loadedFileInfo, fileHandler);
            goto default;
        default:
            break;
    }
}

void main(string[] args) {
	string task = "";
    auto loadedFileInfo = new FileInfo;
    auto fileHandler = new FileHandler;

	validateArgs(args, *loadedFileInfo, task);
    validateFile(*loadedFileInfo, *fileHandler);
    performTask(task, *loadedFileInfo, *fileHandler);
}
