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
 * > Do every data-altering operation on the buffer, save on program exit only
 */

module secwey;

import
    std.file,
    std.conv,
    std.path,
    std.stdio,
    std.regex,
    std.getopt,
    std.random,
    std.datetime,
    std.algorithm,
    core.stdc.stdlib; // for exit()

static import
    std.string, // to avoid confusion with std.algorithm's strip()
    std.ascii;

void displayHelp() {
    writeln("\n"
        ~ "@-=-=--==-=-=-=-=-=-=-=-=-=-=-=-=-@\n"
        ~ "|    List of secway's commands    |\n"
        ~ "H                                 H\n"
        ~ "| f - free                        |\n"
        ~ "H   The default mode. Leads to    H\n"
        ~ "|   the input of another task.    |\n"
        ~ "H c - create                      H\n"
        ~ "|   Appends a new row or column.  |\n"
        ~ "H r - read                        H\n"
        ~ "|   Displays the contents of a    |\n"
        ~ "H   cell or row without altering  H\n"
        ~ "|   any data in the file buffer.  |\n"
        ~ "H u - update                      H\n"
        ~ "|   Changes the contents of a     |\n"
        ~ "H   cell or row. Also executes    H\n"
        ~ "|   the read task by default.     |\n"
        ~ "H d - delete                      H\n"
        ~ "|   Deletes one row or column.    |\n"
        ~ "H s - save                        H\n"
        ~ "|   Saves the altered data        |\n"
        ~ "H   inside a new or existing      H\n"
        ~ "|   file. Prompts for filename.   |\n"
        ~ "H h - help                        H\n"
        ~ "|   Displays this message.        |\n"
        ~ "H q - quit                        H\n"
        ~ "|   Exits secway. If the buffer   |\n"
        ~ "H   has been modified, will ask   H\n"
        ~ "|   if the changes must be saved. |\n"
        ~ "@-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-@"
    );
}

struct FileHandler {
    // [row][cell]
    string[][] fileContents;
    bool dataAltered;
    bool changesSaved = false;

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
                // secway does not yet preserve the spaces included in the file.
                fileContents[lineNumber] ~= to!string(std.string.strip(cellContent));
                loadedFileInfo.cellCount++;
                loadedFileInfo.charCount += cellContent.length;
            }
            loadedFileInfo.rowCount++;
        }

        // Store the number of expected cells per row to avoid re-computing it
        loadedFileInfo.cellsPerRow = primalCellCount;

        // The file's contents have only been read; they're not yet modified
        dataAltered = false;
    }
}

struct FileInfo {
    string filename     = "";
    int cellCount       = 0;
    int rowCount        = 0;
    int charCount       = 0;
    ulong cellsPerRow   = 0;
    bool headerInFile   = false;
}

string validateTask(ref string task) {
    auto possibleTasks = [
        "free":     ["free", "freemode", "f", "normal", "?"],
        "create":   ["create", "c", "insert", "append", "yank"],
        "read":     ["read", "r", "retrieve", "see", "list", "value", "whatis"],
        "update":   ["update", "u", "replace", "change"],
        "delete":   ["delete", "d", "suppress", "nuke", "prune"],
        "save":     ["save", "s", "write"],
        "help":     ["help", "h", "tasks", "wtf"],
        "quit":     ["quit", "q", "exit", "terminate", "bye"]
    ];

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
            ~ "\n>>>>>> Reverting secway to free mode."
        );
        task = "free";
    }

    return task;
}

// Validates arguments provided on program execution
void validateArgs(string[] args, ref FileInfo loadedFileInfo, ref string task) {
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
    
    task = validateTask(task);

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
        ~ "\n* Last modification\n  " ~ to!string(timeLastModified(loadedFileInfo.filename))
    );
}

// Integer helper: When you need a helping hand!
// Be careful to feed the input stripped of CR/LFs
string isUserInputNumeric(char[] input) {
    if (std.string.isNumeric(to!string(input))) {
        int numInput = to!int(input);
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

// Returns the coordinates of a cell or row based on user input
ulong[2] askDataPos(
        const string literal_task,
        ref string[] affectedRow,
        ref FileInfo loadedFileInfo,
        ref FileHandler fileHandler
) {
    // TODO: Allow the user to enter keywords instead of numbers, such as
    //  "first", "last", etc
    // I can sense the sweet, harrowing presence of feature creep getting closer
    ulong rowId, cellId;
    string taskTag = "<" ~ std.string.capitalize(literal_task) ~ ">";

    write("\n" ~ taskTag ~ " Please enter the row number to perform the task on.\n> ");
    RowIdInput:
    rowId = forceUintInput();

    if (rowId > fileHandler.fileContents.length) {
        writeln("[WARN] The row number you provided exceeds the actual number of rows in the file ("
            ~ to!string(loadedFileInfo.rowCount) ~ ")."
            ~ "\n       Please input a valid row number.\n> "
        );
        goto RowIdInput;
    } else {
        affectedRow = fileHandler.fileContents[rowId - 1];
    }

    write("\n" ~ taskTag ~ " Please enter the cell position to look up.\n"
        ~ "Enter zero to interact with the whole row.\n> "
    );

    CellIdInput:
    cellId = forceUintInput(true);

    if (cellId > fileHandler.fileContents[rowId - 1].length) {
        write("[WARN] The cell number you provided exceeds the actual number of cells in the row ("
            ~ to!string(loadedFileInfo.cellsPerRow) ~ ")."
            ~ "\n       Please input a valid cell number.\n> "
        );
        goto CellIdInput;
    }

    // If the second field's value is zero, it means the whole row will be
    //  affected by the ongoing task
    return [rowId, cellId];
}

void read(
    ref FileInfo loadedFileInfo,
    ref FileHandler fileHandler,
    ulong rowId = 0,
    ulong cellId = 0,
    bool dataPosMustBeFetched = true,
    string[] rowToRead = []
) {
    if (dataPosMustBeFetched) {
        ulong[2] dataPos = askDataPos("read", rowToRead, loadedFileInfo, fileHandler);
        rowId = dataPos[0];
        cellId = dataPos[1];
    }

    write("\nDisplaying contents of row " ~ to!string(rowId));
    if (cellId > 0)
        write(", cell " ~ to!string(cellId));
    if (loadedFileInfo.headerInFile)
        write(" (Column header: " ~ fileHandler.fileContents[0][cellId] ~ ")");
    write(":\n ");
    
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

    writeln("<Read> Done.");
}

void writeCSVFile(ref FileInfo loadedFileInfo, ref FileHandler fileHandler) {
    char[] buf_askForDupFile, buf_dupFileName;
    string fileToWriteTo = "";

    // Just in case...
    if (!fileHandler.dataAltered) {
        writeln("[WARN] Secway got to its file-writing step, but fileHandler.dataAltered is false.\n"
            ~ "       Something's not right..."
        );
    }

    write("\nWould you like to save the modified contents in a duplicate file "
        ~ "instead of overwriting the original (" ~ loadedFileInfo.filename ~ ")? (y/n)\n"
        ~ "Entering anything other than \"n\" will default to \"y\".\n> "
    );
    readln(buf_askForDupFile);

    if (std.ascii.toLower(buf_askForDupFile[0]) == 'n') {
        fileToWriteTo = loadedFileInfo.filename;
    } else {
        string baseFileName = baseName(loadedFileInfo.filename, ".csv");
        string unixTimeStamp = to!string((Clock.currTime()).toUnixTime);
        fileToWriteTo = baseFileName ~ unixTimeStamp ~ ".csv";
        write("\nPlease enter the complete name of the new file.\n"
            ~ "(Defaults to " ~ fileToWriteTo ~ " if the input is empty).\n"
            ~ "Caution: Entering a file name with an extension other than"
            ~ " .csv is allowed; proceed carefully.\n> "
        );
        readln(buf_dupFileName);
        string cleanedUpFileNameInput = std.string.chomp(to!string(buf_dupFileName));
        if (cleanedUpFileNameInput != "") {
            fileToWriteTo = cleanedUpFileNameInput;
        }
    }

    File destFile = File(fileToWriteTo, "w+");
    ulong fileLnCursor = 0;
    string buf_lineContents = "";
    string[] rowToWrite;
    while (fileLnCursor < fileHandler.fileContents.length) {
        buf_lineContents = "";
        rowToWrite = fileHandler.fileContents[fileLnCursor];
        foreach (cellCur, cellValue; fileHandler.fileContents[fileLnCursor]) {
            buf_lineContents ~= cellValue;
            if ((cellCur + 1) < rowToWrite.length) {
                buf_lineContents ~= ",";
            }
        }
        destFile.writeln(buf_lineContents);
        fileLnCursor++;
    }

    destFile.close();
    fileHandler.changesSaved = true;
    writeln("File write complete.");
}

// Input validation step only atm
void update(ref FileInfo loadedFileInfo, ref FileHandler fileHandler, bool readFirst = true) {
    ulong rowId, cellId = 0;
    string[] rowToUpdate = [];
    char[] buf_newValue;
    string[] newValue;

    ulong[2] dataPos = askDataPos("update", rowToUpdate, loadedFileInfo, fileHandler);
    rowId = dataPos[0];
    cellId = dataPos[1];

    // TODO: Give the user an option to skip this
    // I should introduce task arguments after the contest, but this is going to
    //  demand quite the refactoring
    if (readFirst) {
        writeln("Transitioning to read mode.");
        read(loadedFileInfo, fileHandler, rowId, cellId, false, rowToUpdate);
        writeln("Reverting to update mode.");
    }

    InputNewValue:
    write("\n<Update> Please enter the new value for this ");
    write((cellId == 0 ? "row" : "cell") ~ ".\n> ");
    readln(buf_newValue);

    string cleanedUpInput = std.string.strip(std.string.chomp(to!string(buf_newValue)));
    if (cleanedUpInput == "") {
        writeln("[INFO] You gave an empty input."
            ~ "\n>>>>>> Aborting edit."
        );
        return;
    }

    newValue = std.string.split(cleanedUpInput, ",");

    if (cellId > 0) {
        if (newValue.length > 1) {
            write("\n[WARN] You have provided more than one comma-separated-value, but only one cell is being edited."
                ~ "\n       Please input a single value, or enter nothing to abort the edit."
            );
            goto InputNewValue;
        } else {
            fileHandler.fileContents[rowId - 1][cellId - 1] = newValue[0]; 
        }
    } else {
        if (newValue.length != loadedFileInfo.cellsPerRow) {
            write("\n[WARN] The number of values you provided ("
                ~ to!string(newValue.length) ~ ") does not match the document's cells-per-row (column) count."
                ~ "\n       Please input a list of exactly " ~ to!string(loadedFileInfo.cellsPerRow)
                ~ " values, separated by commas."
                ~ "\n       Caution: You may enter an empty line, but that will abort the edit."
            );
            goto InputNewValue;
        } else {
            foreach (newCellId, newCellValue; newValue) {
                fileHandler.fileContents[rowId - 1][newCellId] = newCellValue;
            }
        }
    }

    // Caution: The changes are not automatically saved. The user must query the
    //  "save" task in order to write the altered data into a new file.
    fileHandler.dataAltered = true;

    writeln("<Update> Data modified.");
}

// Only supports appending data for now
// TODO: Allow user to insert rows or columns in-between existing ones
void create(ref FileInfo loadedFileInfo, ref FileHandler fileHandler) {
    char[] buf_rowOrColumn, buf_dataToAppend;
    string rowOrColumn;
    string[] dataToAppend;
    // For column insertion specifically:
    ulong expectedRowCount = 0; 
    char[] buf_newHeader;
    string cleanedUpHeader;

    write("\n<Create> Would you like to append a row, or a column? (r/c)\n> ");
    InputNewData:
    readln(buf_rowOrColumn);
    switch (std.ascii.toLower(buf_rowOrColumn[0])) {
        case 'r':
            rowOrColumn = "row";
            break;
        case 'c':
            rowOrColumn = "column";
            break;
        default:
            write("\n<Create> Please input either \"r\" to append a row, or \"c\" to append a column.\n> ");
            goto InputNewData;
    }

    // That chunk of code is awfully similar to update()'s row manipulation
    // I should move that in a separate function later
    if (rowOrColumn == "row") {
        InputNewRow:
        write("\n<Create> Please enter the new value for this row:\n> ");
        readln(buf_dataToAppend);
        string cleanedUpInput = std.string.strip(std.string.chomp(to!string(buf_dataToAppend)));
        if (cleanedUpInput == "") {
            writeln("[INFO] You gave an empty input."
                ~ "\n>>>>>> Aborting data creation."
            );
            return;
        }

        dataToAppend = std.string.split(cleanedUpInput, ",");

        if (dataToAppend.length != loadedFileInfo.cellsPerRow) {
            write("\n[WARN] The number of values you provided ("
                ~ to!string(dataToAppend.length) ~ ") does not match the document's cells-per-row (column) count."
                ~ "\n       Please input a list of exactly " ~ to!string(loadedFileInfo.cellsPerRow)
                ~ " values, separated by commas."
                ~ "\n       Caution: You may enter an empty line, but that will abort the edit."
            );
            goto InputNewRow;
        } else {
            fileHandler.fileContents.length++;
            foreach (newCellId, newCellValue; dataToAppend) {
                fileHandler.fileContents[$ - 1].length++;
                fileHandler.fileContents[$ - 1][newCellId] ~= newCellValue;
            }
        }
    } else {
        InputNewColumn:
        if (loadedFileInfo.headerInFile && cleanedUpHeader == "") {
            write("\n<Create> Please enter the header value for the new column:\n> ");
            readln(buf_newHeader);
            cleanedUpHeader = std.string.strip(std.string.chomp(to!string(buf_newHeader)));
            if (cleanedUpHeader == "") {
                writeln("[INFO] You gave an empty input.");
                goto InputNewColumn;
            }
            expectedRowCount = loadedFileInfo.rowCount - 1;
        }

        if (!loadedFileInfo.headerInFile) {
            expectedRowCount = loadedFileInfo.rowCount;
        }

        write("\n<Create> Please enter the contents of the new column"
            ~ (cleanedUpHeader != "" ? " with header value \"" ~ cleanedUpHeader ~ "\".\n" : ".\n")
            ~ "         Each cell must be separated by commas.\n> "
        );
        readln(buf_dataToAppend);
        string cleanedUpInput = std.string.strip(std.string.chomp(to!string(buf_dataToAppend)));
        if (cleanedUpInput == "") {
            writeln("[INFO] You gave an empty input.");
            goto InputNewColumn;
        }

        dataToAppend = std.string.split(cleanedUpInput, ",");

        if (dataToAppend.length != expectedRowCount) {
            write("\n[WARN] The number of values you provided ("
                ~ to!string(dataToAppend.length) ~ ") does not match the document's row count"
                ~ (loadedFileInfo.headerInFile ? " (header row excluded)." : ".")
                ~ "\n       Please input a list of exactly " ~ to!string(expectedRowCount)
                ~ " values, separated by commas."
                ~ "\n       Caution: You may enter an empty line, but that will abort the edit."
            );
            goto InputNewColumn;
        } else {
            if (cleanedUpHeader != "") {
                // The new column contains a header
                fileHandler.fileContents[0].length++;
                fileHandler.fileContents[0][$ - 1] ~= cleanedUpHeader;
                foreach (rowId, newCellValue; dataToAppend) {
                    fileHandler.fileContents[rowId + 1].length++;
                    fileHandler.fileContents[rowId + 1][$ - 1] ~= newCellValue;
                }
            } else {
                // The new column has no header
                foreach (rowId, newCellValue; dataToAppend) {
                    fileHandler.fileContents[rowId].length++;
                    fileHandler.fileContents[rowId][$ - 1] ~= newCellValue;
                }
            }
        }
    }

    fileHandler.dataAltered = true;

    writeln("<Create> Data appended.");
}

// "delete" is a reserved keyword in Dlang, so I gave that func a longer name
void deleteData(ref FileInfo loadedFileInfo, ref FileHandler fileHandler, bool readFirst = true) {
    ulong rowId, cellId, colId = 0;
    string rowOrColumn;
    char[] buf_rowOrColumn, buf_confirmDeletion;

    write("\n<Delete> Would you like to delete a row, or a column? (r/c)\n> ");
    AskForRowOrCol:
    readln(buf_rowOrColumn);
    switch (std.ascii.toLower(buf_rowOrColumn[0])) {
        case 'r':
            rowOrColumn = "row";
            break;
        case 'c':
            rowOrColumn = "column";
            break;
        default:
            write("\n<Delete> Please input either \"r\" to delete a row, or \"c\" to delete a column.\n> ");
            goto AskForRowOrCol;
    }

    // Asks the user for the data to prune, and prints the data in question
    if (rowOrColumn == "row") {
        DeleteRow:
        write("\n<Delete> Please input the position of the row you would like to delete.\n"
            ~ "Caution: The header row cannot be deleted, so beware of the plus-one offset.\n> "
        );
        rowId = forceUintInput();

        if (loadedFileInfo.headerInFile && rowId == 1) {
            writeln("[WARN] Cannot delete the header row. Please input a higher row position value.");
            goto DeleteRow;
        }

        // TODO: Give the user an option to skip this
        // I should introduce task arguments after the contest, but this is going to
        //  demand quite the refactoring
        if (readFirst) {
            writeln("Transitioning to read mode.");
            read(loadedFileInfo, fileHandler, rowId, 0, false, fileHandler.fileContents[rowId]);
            writeln("Reverting to delete mode.");
        }
    } else {
        // TODO: Column deletion does not work yet. I'll have to fix it.
        // Thrown error: "range is smaller than amount of items to pop".
        DeleteCol:
        write("\n<Delete> Please input the position of the column you would like to delete.\n> ");
        colId = forceUintInput();

        if (colId > loadedFileInfo.cellsPerRow) {
            write("\n[WARN] The column id you provided ("
                ~ to!string(colId) ~ ") does not match the document's cells-per-row (column) count."
                ~ "\n       Please input a value between 1 and "
                ~ to!string(loadedFileInfo.cellsPerRow) ~ ".\n"
            );
            goto DeleteCol;
        }

        writeln("<Delete> Column number "
            ~ to!string(colId)
            ~ (loadedFileInfo.headerInFile ? (" with header value " ~ fileHandler.fileContents[0][colId - 1] ~ " ") : " ")
            ~ "selected."
        );
    }

    write("\n<Delete> Confirm data deletion? (y/n)\n"
        ~ "Entering anything other than \"y\" will default to \"n\".\n> "
    );
    readln(buf_confirmDeletion);
    if (std.ascii.toLower(buf_confirmDeletion[0]) != 'y') {
        writeln("<Delete> Aborting deletion.");
        return;
    }

    // Data-deletion step
    if (rowOrColumn == "row") {
        remove(fileHandler.fileContents, rowId);
        fileHandler.fileContents.length--;
    } else {
        for (int loopRowId = 0; loopRowId < loadedFileInfo.rowCount; loopRowId++) {
            remove(fileHandler.fileContents[loopRowId], colId - 1);
            fileHandler.fileContents[loopRowId].length--;
        }
    }

    fileHandler.dataAltered = true;

    writeln("<Delete> Data deletion completed.");
}

string queryUserForTask(ref string task) {
    char[] buf_taskQuery;

    while (task == "free") {
        write("\nPlease select a task to perform.\n"
            ~ "Type \"h\" or one of its aliases for help. \n"
            ~ "Type \"q\" or one of its aliases to quit. \n> "
        );
        readln(buf_taskQuery);
        task = std.string.chomp(to!string(buf_taskQuery));
        task = validateTask(task);

        if (task == "free") {
            writeln("I am already in free mode.");
        }
    }

    return task;
}

// This function should be reached only after the args provided by the user,
//  aswell as the CSV file itself, have been validated.
void performTask(ref string task, ref FileInfo loadedFileInfo, ref FileHandler fileHandler) {
    char[] buf_confirmQuitAfterChanges;

    TaskSwitch:
    switch (task) {
        // -=-=- Special tasks -=-=-
        case "free":
            goto default;
        case "help":
            displayHelp();
            goto default;
        case "save":
            writeCSVFile(loadedFileInfo, fileHandler);
            goto default;
        // -=-=- For rows -=-=-
        case "create":
            create(loadedFileInfo, fileHandler);
            goto default;
        case "delete":
            deleteData(loadedFileInfo, fileHandler);
            goto default;
        // -=-=- For cells -=-=-
        case "update":
            update(loadedFileInfo, fileHandler);
            goto default;
        // -=-=- For both rows and cells -=-=-
        case "read":
            read(loadedFileInfo, fileHandler);
            goto default;
        default:
            if (task == "quit") {
                if (fileHandler.dataAltered && !fileHandler.changesSaved) {
                    write("\n[WARN] You have altered data in the buffer, but the changes have not been saved.\n"
                        ~ "       Would you like to save before quitting? (y/n)\n"
                        ~ "       Entering anything other than \"y\" will default to \"n\".\n> "
                    );
                    readln(buf_confirmQuitAfterChanges);
                    if (std.ascii.toLower(buf_confirmQuitAfterChanges[0]) == 'y') {
                        goto case "save";
                    }
                }
                writeln("Exiting...\n");
                break;
            } else {
                task = "free";
                task = queryUserForTask(task);
                goto TaskSwitch;
            }
    }
}

void main(string[] args) {
	string task = "";
    auto loadedFileInfo = new FileInfo;
    auto fileHandler = new FileHandler;

	validateArgs(args, *loadedFileInfo, task);
    // If this is triggered, that means the user specified quitting the program
    //  as an initial task. Which is a bit pointless.
    if (task == "quit") {
        writeln("[WHY?] You jumpstart me just to make me quit immediately?"
            ~ "\n       Dude. Uncool. Exiting..."
        );
        exit(1);
    }
    if (task == "save") {
        writeln("[OOPS] The save task has been assigned as my initial task."
            ~ "\n       No data has yet been modified. Falling back on free mode..."
        );
        task = "free";
    }
    validateFile(*loadedFileInfo, *fileHandler);
    performTask(task, *loadedFileInfo, *fileHandler);
}
