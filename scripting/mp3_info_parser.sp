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
	int totalReadBytes = 0;
	
	bool useValveFs = false;
	
	new const String:filePath[] = "soundtrack/101 - annul.mp3";
	if (!FileExists(filePath, useValveFs))
		SetFailState("File does not exist: \"%s\"", filePath);
	
	File file = OpenFile(filePath, "r", useValveFs);
	if (file == null)
		SetFailState("Failed to open file: \"%s\"", filePath);
	
	PrintToServer("# Reading MP3 header for: \"%s\"...", filePath);
	
	// Read header
	int id3v2_header_size;
	{
		decl String:id3v2_header_identifier[3+1];
		file.ReadString(id3v2_header_identifier, 3, 3);
		id3v2_header_identifier[3] = '\0';
		totalReadBytes += 3;
		
		decl String:id3v2_header_version_major[1];
		decl String:id3v2_header_version_revision[1];
		file.ReadString(id3v2_header_version_major, 1, 1);
		file.ReadString(id3v2_header_version_revision, 1, 1);
		totalReadBytes += 2;
		
		decl String:id3v2_header_flags[1];
		file.ReadString(id3v2_header_flags, 1, 1);
		totalReadBytes += 1;
		
		decl String:id3v2_header_size_byte1[1];
		decl String:id3v2_header_size_byte2[1];
		decl String:id3v2_header_size_byte3[1];
		decl String:id3v2_header_size_byte4[1];
		file.ReadString(id3v2_header_size_byte1, 1, 1);
		file.ReadString(id3v2_header_size_byte2, 1, 1);
		file.ReadString(id3v2_header_size_byte3, 1, 1);
		file.ReadString(id3v2_header_size_byte4, 1, 1);
		totalReadBytes += 4;
		
		decl String:id3v2_header_size_buffer[4]; // FIXME
		id3v2_header_size_buffer[0] = id3v2_header_size_byte4[0];
		id3v2_header_size_buffer[1] = id3v2_header_size_byte3[0];
		id3v2_header_size_buffer[2] = id3v2_header_size_byte2[0];
		id3v2_header_size_buffer[3] = id3v2_header_size_byte1[0];
		id3v2_header_size = view_as<int>(id3v2_header_size_buffer[0]);
		
#define ID3v2_REQUIRED_IDENTIFIER "ID3"
#define ID3v2_REQUIRED_VERSION_MAJOR 0x3
		
		if (!StrEqual(id3v2_header_identifier, ID3v2_REQUIRED_IDENTIFIER)) {
			SetFailState("Invalid header id3v2_identifier: \"%s\", expected \"%s\"",
				id3v2_header_identifier, ID3v2_REQUIRED_IDENTIFIER);
		} else if (id3v2_header_version_major[0] != ID3v2_REQUIRED_VERSION_MAJOR) {
			// Version revisions are guaranteed backwards compatible by the ID3v2
			// spec, but major version needs to match to guarantee compatibility.
			SetFailState("Unsupported header id3v2_version_major: \"%d\", expected \"%d\"",
				id3v2_header_version_major, ID3v2_REQUIRED_VERSION_MAJOR);
		} else {
#define UNUSED_HEADER_FLAG_BITS (8 - 3)
			for (int i = 0; i < UNUSED_HEADER_FLAG_BITS; ++i) {
				if (id3v2_header_flags[0] & (1 << i)) {
					// The ID3v2 spec declares all unused bits should be unset.
					SetFailState("id3v2_flags bit %i was set, but it shouldn't be; corrupted file?", i);
				}
			}
		}
		if (id3v2_header_size <= 0 || id3v2_header_size >= FileSize(filePath, useValveFs)) {
			SetFailState("Invalid id3v2_size: %d (expected range 1-%d)",
				id3v2_header_size, FileSize(filePath, useValveFs));
		}
		
		PrintToServer("-- id3v2_header_identifier: %s", id3v2_header_identifier);
		PrintToServer("-- id3v2_header_version: %x (major), %x (revision)",
			id3v2_header_version_major, id3v2_header_version_revision);
		PrintToServer("-- id3v2_header_flags:\n\tUnsynchronisation: %s\n\tExtended header: %s\
\n\tExperimental indicator: %s\n\tInvalidly set unused flag bits: %s",
			(id3v2_header_flags[0] & (1 << 7) ? "yes" : "no"),
			(id3v2_header_flags[0] & (1 << 6) ? "yes" : "no"),
			(id3v2_header_flags[0] & (1 << 5) ? "yes" : "no"),
			"no"); // This last one is implied by us not SetFailState'ing by now.
		PrintToServer("-- id3v2_size: %d bytes", id3v2_header_size);
		
		PrintToServer("# Finished reading MP3 header.");
	}
	
	// Read extended header
	{
		decl String:nextFourBytes[4];
		if (file.ReadString(nextFourBytes, 4, 4) != sizeof(nextFourBytes)) {
			SetFailState("Failed to write required num of chars");
		}
		totalReadBytes += 4;
		
		int interpretAsExtHeaderSize = view_as<int>(nextFourBytes[0]);
		
		bool isExtHeader = false;
		int allowedExtHeaderSizes[] = { 6, 10 };
		for (int i = 0; i < sizeof(allowedExtHeaderSizes); ++i) {
			if (interpretAsExtHeaderSize == allowedExtHeaderSizes[i]) {
				isExtHeader = true;
				break;
			}
		}
		
		// TODO: test ext header with an example file containing such data
		if (isExtHeader) {
			PrintToServer("Entering Extended header (size %d)", interpretAsExtHeaderSize);
			
			decl String:id3v2_ext_header_flags_byte1[1];
			decl String:id3v2_ext_header_flags_byte2[1];
			file.ReadString(id3v2_ext_header_flags_byte1, 1, 1);
			file.ReadString(id3v2_ext_header_flags_byte2, 1, 1);
			totalReadBytes += 2;
			if (id3v2_ext_header_flags_byte1[0] != 0x0) {
				SetFailState("First byte of extended flag header should be zeroed (was %b)",
					id3v2_ext_header_flags_byte1[0]);
			}
			bool isCrcDataPresent = (id3v2_ext_header_flags_byte2[0] & (1 << 7)) ? true : false;
			
			int ext_padding_size = interpretAsExtHeaderSize - 2;
			decl String:id3v2_ext_header_padding[ext_padding_size];
			file.ReadString(id3v2_ext_header_padding, ext_padding_size, ext_padding_size);
			totalReadBytes += ext_padding_size;
			
			if (isCrcDataPresent) {
				decl String:id3v2_ext_header_crc_data[4];
				file.ReadString(id3v2_ext_header_crc_data, 4, 4);
				totalReadBytes += 4;
				PrintToServer("Total frame CRC: %x", id3v2_ext_header_crc_data[0]);
			}
		}
		
		// Entering frame header
		new const String:id3v2_declared_frames[][][] = {
			{ "AENC", "Audio encryption" },
			{ "APIC", "Attached picture" },
			{ "COMM", "Comments" },
			{ "COMR", "Commercial frame" },
			{ "ENCR", "Encryption method registration" },
			{ "EQUA", "Equalization" },
			{ "ETCO", "Event timing codes" },
			{ "GEOB", "General encapsulated object" },
			{ "GRID", "Group identification registration" },
			{ "IPLS", "Involved people list" },
			{ "LINK", "Linked information" },
			{ "MCDI", "Music CD identifier" },
			{ "MLLT", "MPEG location lookup table" },
			{ "OWNE", "Ownership frame" },
			{ "PRIV", "Private frame" },
			{ "PCNT", "Play counter" },
			{ "POPM", "Popularimeter" },
			{ "POSS", "Position synchronisation frame" },
			{ "RBUF", "Recommended buffer size" },
			{ "RVAD", "Relative volume adjustment" },
			{ "RVRB", "Reverb" },
			{ "SYLT", "Synchronized lyric/text" },
			{ "SYTC", "Synchronized tempo codes" },
			{ "TALB", "Album/Movie/Show title" },
			{ "TBPM", "BPM (beats per minute)" },
			{ "TCOM", "Composer" },
			{ "TCON", "Content type" },
			{ "TCOP", "Copyright message" },
			{ "TDAT", "Date" },
			{ "TDLY", "Playlist delay" },
			{ "TENC", "Encoded by" },
			{ "TEXT", "Lyricist/Text writer" },
			{ "TFLT", "File type" },
			{ "TIME", "Time" },
			{ "TIT1", "Content group description" },
			{ "TIT2", "Title/songname/content description" },
			{ "TIT3", "Subtitle/Description refinement" },
			{ "TKEY", "Initial key" },
			{ "TLAN", "Language(s)" },
			{ "TLEN", "Length" },
			{ "TMED", "Media type" },
			{ "TOAL", "Original album/movie/show title" },
			{ "TOFN", "Original filename" },
			{ "TOLY", "Original lyricist(s)/text writer(s)" },
			{ "TOPE", "Original artist(s)/performer(s)" },
			{ "TORY", "Original release year" },
			{ "TOWN", "File owner/licensee" },
			{ "TPE1", "Lead performer(s)/Soloist(s)" },
			{ "TPE2", "Band/orchestra/accompaniment" },
			{ "TPE3", "Conductor/performer refinement" },
			{ "TPE4", "Interpreted, remixed, or otherwise modified by" },
			{ "TPOS", "Part of a set" },
			{ "TPUB", "Publisher" },
			{ "TRCK", "Track number/Position in set" },
			{ "TRDA", "Recording dates" },
			{ "TRSN", "Internet radio station name" },
			{ "TRSO", "Internet radio station owner" },
			{ "TSIZ", "Size" },
			{ "TSRC", "ISRC (international standard recording code)" },
			{ "TSSE", "Software/Hardware and settings used for encoding" },
			{ "TYER", "Year" },
			{ "TXXX", "User defined text information frame" },
			{ "UFID", "Unique file identifier" },
			{ "USER", "Terms of use" },
			{ "USLT", "Unsychronized lyric/text transcription" },
			{ "WCOM", "Commercial information" },
			{ "WCOP", "Copyright/Legal information" },
			{ "WOAF", "Official audio file webpage" },
			{ "WOAR", "Official artist/performer webpage" },
			{ "WOAS", "Official audio source webpage" },
			{ "WORS", "Official internet radio station homepage" },
			{ "WPAY", "Payment" },
			{ "WPUB", "Publishers official webpage" },
			{ "WXXX", "User defined URL link frame" },
		};
		int num_declared_frames = sizeof(id3v2_declared_frames);
		
		PrintToServer("Entering frame data at %d of %d bytes read.",
			totalReadBytes, id3v2_header_size);
		
		while (totalReadBytes < id3v2_header_size) { // FIXME
			decl String:interpretAsFrameID[4+1];
			interpretAsFrameID[0] = nextFourBytes[0];
			interpretAsFrameID[1] = nextFourBytes[1];
			interpretAsFrameID[2] = nextFourBytes[2];
			interpretAsFrameID[3] = nextFourBytes[3];
			interpretAsFrameID[4] = '\0';
			
			bool recognized_header = false;
			for (int i = 0; i < num_declared_frames; ++i) {
				if (StrEqual(interpretAsFrameID, id3v2_declared_frames[i][0])) {
					PrintToServer("Entering Frame Header %s (%s)",
						interpretAsFrameID, id3v2_declared_frames[i][1]);
					recognized_header = true;
					break;
				}
			}
			
			if (!recognized_header) {
				PrintToServer("Unrecognized frame header \"%s\"; possibly user-defined.",
					interpretAsFrameID);
			}
			
			decl String:frameSizeByte1[1];
			decl String:frameSizeByte2[1];
			decl String:frameSizeByte3[1];
			decl String:frameSizeByte4[1];
			file.ReadString(frameSizeByte1, 1, 1);
			file.ReadString(frameSizeByte2, 1, 1);
			file.ReadString(frameSizeByte3, 1, 1);
			file.ReadString(frameSizeByte4, 1, 1);
			totalReadBytes += 4;
			decl String:frame_size_buffer[4];
			frame_size_buffer[0] = frameSizeByte4[0];
			frame_size_buffer[1] = frameSizeByte3[0];
			frame_size_buffer[2] = frameSizeByte2[0];
			frame_size_buffer[3] = frameSizeByte1[0];
			int frame_size = view_as<int>(frame_size_buffer[0]);
			
			decl String:frameFlagByte1_StatusMsgs[1];
			decl String:frameFlagByte2_EncodingInfo[1];
			file.ReadString(frameFlagByte1_StatusMsgs, 1, 1);
			file.ReadString(frameFlagByte2_EncodingInfo, 1, 1);
			totalReadBytes += 2;
			
#define FRAME_STATUS_MSG_TAG_ALTER_PRESERVATION		(1 << 7) // FIXME: possibly wrong byte order?
#define FRAME_STATUS_MSG_FILE_ALTER_PRESERVATION	(1 << 6)
#define FRAME_STATUS_MSG_READ_ONLY					(1 << 5)

#define FRAME_ENCODING_INFO_COMPRESSION				(1 << 7)
#define FRAME_ENCODING_INFO_ENCRYPTION				(1 << 6)
#define FRAME_ENCODING_INFO_CONTAINS_GROUP_ID_INFO	(1 << 5)

			decl String:frameData[frame_size];
			file.ReadString(frameData, frame_size, frame_size);
			totalReadBytes += frame_size;
			PrintToServer("Frame size: %d", frame_size);
			PrintToServer("Frame flags:\n\tStatus msgs: %b\n\tEncoding info: %b",
				frameFlagByte1_StatusMsgs[0], frameFlagByte2_EncodingInfo[0]);
			PrintToServer("\tFrame status: Tag alter preservation: %s",
				((frameFlagByte1_StatusMsgs[0] & FRAME_STATUS_MSG_TAG_ALTER_PRESERVATION) ? "yes" : "no"));
			PrintToServer("\tFrame status: File alter preservation: %s",
				((frameFlagByte1_StatusMsgs[0] & FRAME_STATUS_MSG_FILE_ALTER_PRESERVATION) ? "yes" : "no"));
			PrintToServer("\tFrame status: Read only: %s",
				((frameFlagByte1_StatusMsgs[0] & FRAME_STATUS_MSG_READ_ONLY) ? "yes" : "no"));
			PrintToServer("\tEncoding info: This frame is compressed: %s",
				((frameFlagByte2_EncodingInfo[0] & FRAME_ENCODING_INFO_COMPRESSION) ? "yes" : "no"));
			PrintToServer("\tEncoding info: This frame is encrypted: %s",
				((frameFlagByte2_EncodingInfo[0] & FRAME_ENCODING_INFO_ENCRYPTION) ? "yes" : "no"));
			PrintToServer("\tEncoding info: This frame contains group information: %s",
				((frameFlagByte2_EncodingInfo[0] & FRAME_ENCODING_INFO_CONTAINS_GROUP_ID_INFO) ? "yes" : "no"));
			PrintToServer("Frame raw data: \"%x\"", frameData);
		}
	}
	
	PrintToServer("Read %d bytes of %d from ID3v2 header total.", totalReadBytes, id3v2_header_size);
	if (totalReadBytes != id3v2_header_size) {
		PrintToServer("\tRead size mismatch!");
	}
	
	file.Close();
}