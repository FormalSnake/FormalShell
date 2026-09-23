import QtQuick
import QtTest
import "../shell/Radio/stations.js" as Stations

TestCase {
    name: "RadioCliamp"

    readonly property string m3u: "#EXTM3U\n"
        + "#EXTINF:-1,Lofi\nhttps://radio.cliamp.stream/lofi/stream\n"
        + "#EXTINF:-1,Omarchy\nhttps://radio.cliamp.stream/omarchy/stream\n"
        + "#EXTINF:-1,Elsewhere\nhttps://example.com/x/stream\n"
        + "#EXTINF:-1,NCS Drum & Bass\r\nhttps://radio.cliamp.stream/ncs-dnb/stream\r\n"
        + "https://radio.cliamp.stream/lofi/stream\n"

    function test_channels_parse_without_omarchy() {
        var rows = Stations.parseCliamp(m3u);
        compare(rows.length, 2);
        compare(rows[0].uuid, "cliamp:lofi");
        compare(rows[0].name, "Lofi");
        compare(rows[1].uuid, "cliamp:ncs-dnb");
        compare(rows[1].name, "NCS Drum & Bass");
        verify(Stations.playable(rows[1]));
        compare(rows[1].latitude, null);
    }

    function test_not_an_m3u() {
        compare(Stations.parseCliamp("<html>"), null);
        compare(Stations.parseCliamp(null), null);
    }

    function test_a_channel_survives_a_save() {
        var state = Stations.parseState(JSON.stringify({ favorites: Stations.parseCliamp(m3u), recent: [] }));
        compare(state.favorites.length, 2);
        compare(state.favorites[0].uuid, "cliamp:lofi");
    }
}
