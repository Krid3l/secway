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
 * > The software must be able to alter the file's cells, headers included
 * > The software must be able to delete individual rows, headers excluded
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
    bool headersInFile  = false;
}

// Validates arguments provided on program execution
void validateArgs(string[] args, ref FileInfo loadedFileInfo, ref string task) {
    string[] possibleTasks = [
        "free", "freemode", "f",
        "create", "c",
        "read", "r",
        "update", "u",
        "delete", "d"
    ];

    auto headerArgValues = [
        "yes": ["yes", "y", "true", "yeah", "aye", "oui"],
        "no": ["no", "n", "false", "nope", "nah", "non"]
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
    
    if (!possibleTasks.canFind(task)) {
        writeln("[WARN] Provided task argument is "
            ~ (task == "" ? "empty" : "invalid") ~ "." 
            ~ "\n>>>>>> Reverting secway to free mode."
        );
        task = "";
    }

    if (headerArg == "") {
        writeln("[INFO] No header argument provided."
            ~ "\n>>>>>> Secway will assume there's no header in the file."
        );
    } else if (headerArgValues["yes"].canFind(headerArg)) {
        loadedFileInfo.headersInFile = true;
    } else {
        if (!headerArgValues["no"].canFind(headerArg)) {
            writeln("[WARN] The provided header argument is invalid."
                ~ "\n>>>>>> Secway will assume there's no header in the file."
            );
        }
    }
}

// Ensure that the file is a valid CSV file as per the IETF RFC 4180 standard
void validateFile(ref FileInfo loadedFileInfo, FileHandler fileHandler) {
    // Deliberately, I won't pass a file pointer throught the whole of Secway.
    // Instead, I'm just going to open and close the CSV file only when
    //  operations ought to be performed. (e.g. in FileHandler.parseContents())
    fileHandler.parseContents(loadedFileInfo);

    writeln("\n  Info about " ~ loadedFileInfo.filename ~ ":\n"
        ~ "\n  Character count (excluding separators and CL/RFs)\n> " ~ to!string(loadedFileInfo.charCount)
        ~ "\n  Cell count\n> " ~ to!string(loadedFileInfo.cellCount)
        ~ "\n  Row count\n> " ~ to!string(loadedFileInfo.rowCount)
        ~ "\n  Headers? (user-specified)\n> " ~ (loadedFileInfo.headersInFile ? "yes" : "no")
    );
}

void main(string[] args) {
	string task = "";
    auto loadedFileInfo = new FileInfo;
    auto fileHandler = new FileHandler;

	validateArgs(args, *loadedFileInfo, task);
    validateFile(*loadedFileInfo, *fileHandler);
}
