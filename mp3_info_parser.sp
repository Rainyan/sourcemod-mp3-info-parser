#pragma semicolon 1

#include <sourcemod>

#define PLUGIN_VERSION "0.1"

public Plugin myinfo = {
	name = "MP3 Info Parser",
	description = "MP3 ID3v2 Tag Parser",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-mp3-info-parser"
};

public void OnPluginStart()
{
	bool useValveFs = false;
	
	new const String:filePath[] = "soundtrack/101 - annul.mp3";
	if (!FileExists(filePath, useValveFs))
		SetFailState("File does not exist: \"%s\"", filePath);
	
	File file = OpenFile(filePath, "r", useValveFs);
	if (file == null)
		SetFailState("Failed to open file: \"%s\"", filePath);
	
	PrintToServer("# Reading MP3 header for: \"%s\"...", filePath);
	
	// Read header
	decl String:id3v2_identifier[3+1];
	file.ReadString(id3v2_identifier, 3, 3);
	id3v2_identifier[3] = '\0';
	
	decl String:id3v2_version_major[1];
	decl String:id3v2_version_revision[1];
	file.ReadString(id3v2_version_major, 1, 1);
	file.ReadString(id3v2_version_revision, 1, 1);
	
	decl String:id3v2_flags[1];
	file.ReadString(id3v2_flags, 1, 1);
	
	decl String:id3v2_size_byte1[1];
	decl String:id3v2_size_byte2[1];
	decl String:id3v2_size_byte3[1];
	decl String:id3v2_size_byte4[1];
	file.ReadString(id3v2_size_byte1, 1, 1);
	file.ReadString(id3v2_size_byte2, 1, 1);
	file.ReadString(id3v2_size_byte3, 1, 1);
	file.ReadString(id3v2_size_byte4, 1, 1);
	
	decl String:id3v2_size_buffer[4];
	id3v2_size_buffer[0] = id3v2_size_byte4[0];
	id3v2_size_buffer[1] = id3v2_size_byte3[0];
	id3v2_size_buffer[2] = id3v2_size_byte2[0];
	id3v2_size_buffer[3] = id3v2_size_byte1[0];
	int id3v2_size = view_as<int>(id3v2_size_buffer[0]);
	
#define ID3v2_REQUIRED_IDENTIFIER "ID3"
#define ID3v2_REQUIRED_VERSION_MAJOR 0x3
	
	if (!StrEqual(id3v2_identifier, ID3v2_REQUIRED_IDENTIFIER)) {
		SetFailState("Invalid header id3v2_identifier: \"%s\", expected \"%s\"",
			id3v2_identifier, ID3v2_REQUIRED_IDENTIFIER);
	} else if (id3v2_version_major[0] != ID3v2_REQUIRED_VERSION_MAJOR) {
		// Version revisions are guaranteed backwards compatible by the ID3v2
		// spec, but major version needs to match to guarantee compatibility.
		SetFailState("Unsupported header id3v2_version_major: \"%d\", expected \"%d\"",
			id3v2_version_major, ID3v2_REQUIRED_VERSION_MAJOR);
	} else {
#define UNUSED_HEADER_FLAG_BITS (8 - 3)
		for (int i = 0; i < UNUSED_HEADER_FLAG_BITS; ++i) {
			if (id3v2_flags[0] & (1 << i)) {
				// The ID3v2 spec declares all unused bits should be unset.
				SetFailState("id3v2_flags bit %i was set, but it shouldn't be; corrupted file?", i);
			}
		}
	}
	if (id3v2_size <= 0 || id3v2_size >= FileSize(filePath, useValveFs)) {
		SetFailState("Invalid id3v2_size: %d (expected range 1-%d)",
			id3v2_size, FileSize(filePath, useValveFs));
	}
	
	PrintToServer("-- id3v2_identifier: %s", id3v2_identifier);
	PrintToServer("-- id3v2_version: %x (major), %x (revision)",
		id3v2_version_major, id3v2_version_revision);
	PrintToServer("-- id3v2_flags:\n\tUnsynchronisation: %s\n\tExtended header: %s\
\n\tExperimental indicator: %s\n\tInvalidly set unused flag bits: %s",
		(id3v2_flags[0] & (1 << 7) ? "yes" : "no"),
		(id3v2_flags[0] & (1 << 6) ? "yes" : "no"),
		(id3v2_flags[0] & (1 << 5) ? "yes" : "no"),
		"no"); // This last one is implied by us not SetFailState'ing by now.
	PrintToServer("-- id3v2_size: %d bytes", id3v2_size);
	
	PrintToServer("# Finished reading MP3 header.");
	
	file.Close();
}