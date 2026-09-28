import QtQuick
import QtTest
import "../shell/Airplay/model.js" as AM

TestCase {
    name: "AirplayModel"

    // Real shapes off FDH2/UxPlay's own source (uxplay.cpp) at HEAD, 2026-09-28.

    function test_parseMetadata_reads_every_known_field() {
        var m = AM.parseMetadata("Album artist: The Band\nAlbum: A Record\nArtist: The Band\nGenre: Rock\nTitle: A Song\n");
        compare(m.title, "A Song");
        compare(m.artist, "The Band");
        compare(m.album, "A Record");
        compare(m.genre, "Rock");
    }

    function test_parseMetadata_missing_field_is_blank() {
        var m = AM.parseMetadata("Title: A Song\n");
        compare(m.title, "A Song");
        compare(m.artist, "");
        compare(m.album, "");
    }

    function test_parseMetadata_no_data_placeholder_is_all_blank() {
        var m = AM.parseMetadata("no data\n");
        compare(m.title, "");
        compare(m.artist, "");
        compare(m.album, "");
        compare(m.genre, "");
    }

    function test_parseMetadata_empty_text() {
        var m = AM.parseMetadata("");
        compare(m.title, "");
    }

    // "Album artist" must not be read as "Album": distinct keys, not a prefix
    // match.
    function test_parseMetadata_album_artist_does_not_leak_into_album() {
        var m = AM.parseMetadata("Album artist: Someone Else\n");
        compare(m.album, "");
    }

    function test_isPlaceholderCover() {
        compare(AM.isPlaceholderCover(95), true);
        compare(AM.isPlaceholderCover(94), false);
        compare(AM.isPlaceholderCover(0), false);
        compare(AM.isPlaceholderCover(48213), false);
    }

    function test_parseLine_connected() {
        var e = AM.parseLine("connection request from Kyan's iPhone (iPhone15,2) with deviceID = 11:22:33:44:55:66");
        compare(e.type, "connected");
        compare(e.name, "Kyan's iPhone");
        compare(e.model, "iPhone15,2");
        compare(e.deviceId, "11:22:33:44:55:66");
    }

    function test_parseLine_disconnected_either_spacing() {
        compare(AM.parseLine("***ERROR lost connection with client (network problem?)").type, "disconnected");
        compare(AM.parseLine("*** ERROR lost connection with client (network problem?)").type, "disconnected");
    }

    function test_parseLine_unrelated_is_null() {
        compare(AM.parseLine("UxPlay 1.73 an AirPlay Unix mirroring server"), null);
        compare(AM.parseLine(""), null);
        compare(AM.parseLine("   "), null);
    }

    function test_parseLine_error() {
        var e = AM.parseLine("*** ERROR: could not start mDNS advertising");
        compare(e.type, "error");
    }

    function test_resolveName_prefers_configured() {
        compare(AM.resolveName("Kyan's Desk", "g815"), "Kyan's Desk");
    }

    function test_resolveName_falls_back_to_hostname() {
        compare(AM.resolveName("", "g815"), "g815");
    }

    function test_resolveName_falls_back_to_shell_name() {
        compare(AM.resolveName("", ""), "FormalShell");
    }
}
