const Websocket = require("ws")
const crypto = require("crypto")

const PORT = process.env.PORT || 8080


// the below list of packet types only includes those used by the
//   signaling server the game instances have a more extensive list
//   of packet types
const PacketTypes = {
    KeepAlive : 0,
    InvalidDestination : 1,
    PeerAssignedID : 2,
    DeclareLobbyHost : 3,
    LobbyHostSettingsChanged : 4,
    ListLobbiesRequest : 5,
    LobbyDict : 6,
    LobbyDictNotNeeded : 7
}

// Num doesn't contain 0 since player peer ids are type Number, which means
// that id = 0123 is the same as id = 123. This change is to preserve id length
const NUM = ["1","2","3","4","5","6","7","8","9"]
const PEER_ID_LEN = 4

const keepAliveInterval = 45000 // ms
var keepAliveTimerRunning = false

class Peer {
    /**
     * @param {number} peer_id
     * @param {Websocket} ws
     */
    constructor(peer_id, ws) {
        this.id = peer_id
        this.ws = ws

        // defined when/if this peer declares itself as a lobby host
        this.accepting_new_players // Number
        this.lobby_size            // Number
        this.curr_player_count     // Number
        this.lobby_name            // String
        this.password_enabled      // Boolean

        // The "mail distribution center", aka the Peers instance, handles websocket events
        ws.onmessage = peers.receive.bind(peers)
        ws.onclose = (_event) => peers.remove_peer(this.id)
        ws.onerror = (_event) => peers.remove_peer(this.id)
    }
}

/**
 * A Peers instance resembles a mail distribution center (refered to as MDC below).
 * Packets come in and if they have a json structure and a valid address that the MDC
 *   knows then the packet is forwarded to that address only if the packet destination
 *   isn't the MDC
 */
class Peers {
    constructor() {
        this.player_peers = new Map // Map[Number, Peer]
        this.lobby_peers = new Map  // Map[String, Peer]

        this.lobby_hash // String
        this.hash_lobbies()
    }

    /**
     * Add a new Peer instance to player_peers with the given websocket and
     * send the assigned peer_id to the other end of the websocket connection
     * @param {Websocket} ws
     */
    add_peer(ws) {
        var peer_id = this.gen_player_peer_id()
        console.log("added peer with id " + peer_id)

        this.player_peers.set(peer_id, new Peer(peer_id, ws))
        this.send(PacketTypes.PeerAssignedID, peer_id)

        // if the total peer count went from 0 to 1, aka the server went from idle to
        //   being used, start the keep alive timer
        // the keep alive timer isnt always running in order to limit resource usage
        //   while the server is idle
        if (!keepAliveTimerRunning) {
            console.log("Starting keep alive timer, total peer count === 1")
            keepAliveTimerRunning = true
            this.start_keep_alive_timer()
        }
    }

    /**
     * Remove a peer from either lobby_peers or player_peer, depending on
     * wether the type of peer_id is string or not
     * @param {number | string} peer_id
     */
    remove_peer(peer_id) {
        console.log("removing peer " + peer_id)

        if (typeof(peer_id) === "number") this.player_peers.delete(peer_id)
        else {
            this.lobby_peers.delete(peer_id)
            this.hash_lobbies()
        }
        
        console.log(`peers post removal:\n\tPlayers: ${[...this.player_peers.keys()]}\n\tLobbies: ${[...this.lobby_peers.keys()]}`)
    }

    /**
     * Return the Peer object corresponding to the given peer_id or undefined,
     * depending on wether a Peer was found
     * @param {number | string} peer_id
     * @returns {undefined | Peer}
     */
    get_peer(peer_id) {
        if (typeof(peer_id) == "string") return this.lobby_peers.get(peer_id)
        else return this.player_peers.get(peer_id)
    }

    /**
     * Returns the total number of connected peers
     * @returns {number}
     */
    get_total_peer_count() {
        return this.lobby_peers.size + this.player_peers.size
    }

    /**
     * Send a packet through the websocket connection of the Peer object
     * corresponding to dst. dst is used as a peer id. The packet will contain
     * a type, dst and src key-value pair as well as everything in the data
     * argument
     * @param {number} type
     * @param {number | string} dst
     * @param {JSON} data
     * @returns {bool} success?
     */
    send(type, dst, data = {}) {
        console.log("sending packet to " + dst)
        console.log(`\ttype: ${type}, dst: ${dst}, data:`, data)

        var dst_peer = this.get_peer(dst)
        if (dst_peer != undefined) {
            var formatted_data_json = Object.assign({"type": type, "dst": dst, "src": -1}, data)
            dst_peer.ws.send(JSON.stringify(formatted_data_json))
            return true
        }
        return false
    }

    /**
     * This is called whenever a websocket connection in any Peer object
     * gets a message/packet. The packet data is parsed and converted to
     * a Map object (packet_json). If it contains certain expected keys
     * the packet is either parsed by the signaling server or forwarded
     * to its destination Peer.
     * 
     * The packet is dropped if it cant be converted to a Map object or
     * if it doesnt contain the expected keys.
     * @param {Websocket.MessageEvent} event
     */
    receive(event) {
        console.log("received packet")
        var packet = event.data
        var packet_json = try_parse_json(packet)

        console.log(`\t${packet}`)

        // if the packet valid
        if (packet_json != undefined) {
            console.log("\tpacket json valid")

            // if the packet contains the expected data
            if (packet_json.has("type") && packet_json.has("dst") && packet_json.has("src")) {
                console.log("\tpacket has type, dst and src")
                console.log("\ttype:", packet_json.get("type"), typeof(packet_json.get("type")), "\n\tdst:", packet_json.get("dst"), typeof(packet_json.get("dst")), "\n\tsrc:", packet_json.get("src"), typeof(packet_json.get("src")))

                // if packet destination is signaling server
                if (packet_json.get("dst") === -1) {
                    console.log("\tfor signaling server")
                    this.parse_packet(packet_json)
                }

                // if packet destination is a either a player or lobby peer
                else {
                    console.log("\tfor peer " + packet_json.get("dst"))
                    var dst_peer = this.get_peer(packet_json.get("dst"))

                    if (dst_peer != undefined) dst_peer.ws.send(packet)
                    else this.send(PacketTypes.InvalidDestination, packet_json.get("src"))
                }
            }
        }
    }

    /**
     * Parse a packet who's destination is the signaling server
     * @param {Map} packet_json 
     */
    parse_packet(packet_json) {
        console.log("parsing packet")
        var src_peer = this.get_peer(packet_json.get("src"))
        var packet_type = packet_json.get("type")

        console.log(`\t${packet_type}`)

        switch (packet_type) {
            // no action needed if the packet type is KeepAlive
            case PacketTypes.KeepAlive: break

            // The src has declared they wish to be a lobby host
            case PacketTypes.DeclareLobbyHost:
                // gen the new lobby peer id
                var lobby_peer_id = this.gen_lobby_peer_id()
                
                // unpack the lobby settings
                src_peer.accepting_new_players = packet_json.get("accepting_new_players")
                src_peer.lobby_size = packet_json.get("lobby_size")
                src_peer.curr_player_count = packet_json.get("curr_player_count")
                src_peer.lobby_name = packet_json.get("lobby_name")
                src_peer.password_enabled = packet_json.get("password_enabled")

                // move the Peer object from the player_peers map to
                // the lobby_peers map
                this.lobby_peers.set(lobby_peer_id, src_peer)
                this.player_peers.delete(src_peer.id)

                // update the peer object's id
                src_peer.id = lobby_peer_id
                this.send(PacketTypes.PeerAssignedID, lobby_peer_id)
                this.hash_lobbies()
                break

            // a lobby setting has changed in src
            case PacketTypes.LobbyHostSettingsChanged:
                var [property_name, new_value] = packet_json.get("setting")
                src_peer[property_name] = new_value
                this.hash_lobbies()
                break

            // The src has requested a list of all active lobbies
            case PacketTypes.ListLobbiesRequest:
                // if the hash provided by the player doesnt match the current lobby hash:
                //   send all lobbies and the lobby_hash
                if (packet_json.get("hash") != this.lobby_hash) {
                    console.log(packet_json.get("hash") + ` != ` + this.lobby_hash)
                    this.send(PacketTypes.LobbyDict, src_peer.id, {"lobbies": this.list_lobbies(), "hash": this.lobby_hash})
                }
                // if the hash provided by the player is the same as the current hash then theres
                //   no need to send the entire lobby list
                // therefore just send an acknowledgement packet
                else this.send(PacketTypes.LobbyDictNotNeeded, src_peer.id)
                break
        }
    }

    start_keep_alive_timer() {
        console.log("Starting keep alive timer")
        setTimeout((() => this.send_keep_alive()).bind(this), keepAliveInterval)
    }

    /**
     * Send a packet to every cpnnected peer to prevent the websocket connections from closing
     * @param {number | string} dst
     */
    send_keep_alive() {
        console.log("\nSending keepAlive packets")
        for (let lobby_id of this.lobby_peers.keys()) this.send(PacketTypes.KeepAlive, lobby_id)
        for (let player_id of this.player_peers.keys()) this.send(PacketTypes.KeepAlive, player_id)

        // renew the keep alive timer only if the server is being used
        if (this.get_total_peer_count()) this.start_keep_alive_timer()
        else {
            keepAliveTimerRunning = false
            console.log("Didnt renew keep alive timer")
        }
        console.log("")
    }

    /**
     * Retuns a JSON object where the keys are lobby ids
     * and the values are JSON object with lobby info
     * @returns {{}}
     */
    list_lobbies() {
        var lobbies = {}
        for (let lobby_id of this.lobby_peers.keys()) {
            lobbies[lobby_id] = {}
            var lobby_peer = this.get_peer(lobby_id)

            // go through all properties in the current lobby peer object
            //   and assign them to the lobbies object
            // the `id` property is skipped because it's a JSON key, and
            //   is thereby already being sent
            // the `ws` property is skipped because its only useful to the
            //   signaling server (also its a js class instance and cant be sent)
            for (var [property_name, value] of Object.entries(lobby_peer)) {
                if (property_name === "id" || property_name === "ws") continue
                lobbies[lobby_id][property_name] = value
            }
        }

        return lobbies
    }

    /**
     * Generate a JSON object of lobby ids and their data, stringify it
     * and hash it using md5. The hash string is used for version
     * control when peers ask for the list of lobbies. If the peer and
     * signal server have identical lobby hash strings then there's no
     * need to send the entire list
     */
    hash_lobbies() {
        this.lobby_hash = md5_hash_string(JSON.stringify(this.list_lobbies()))
        console.log(`set lobby list hash to "${this.lobby_hash}"`)
        console.log(this.list_lobbies(), "\n")
    }

    /**
     * Helper function that generates a Number with PEER_ID_LEN digits
     * @returns {number}
     */
    _gen_id() {
        var ID = ""
        for (let i = 0; i < PEER_ID_LEN; i++) {
            ID += NUM[~~(Math.random() * NUM.length)]
        }
        return Number(ID)
    }
    
    /**
     * Generate a unique id of type player and length PEER_ID_LEN
     * @returns {number} ID
     */
    gen_player_peer_id() {
        var ID = this._gen_id()
        while (this.player_peers.has(ID)) {ID = this._gen_id()}
        return ID
    }

    /**
     * Generate a unique id of type lobby and length PEER_ID_LEN
     * Lobby ids are like player ids but with an "L" prefix
     * @returns {String} ID
     */
    gen_lobby_peer_id() {
        var ID = "L" + this._gen_id()
        while (this.lobby_peers.has(ID)) {ID = "L" + this._gen_id()}
        return ID
    }
}

/**
 * Try to parse text into a Map object
 * Returns a Map object on success, or undefined on failure
 * @param {string} text
 * @returns {undefined | Map}
 */
function try_parse_json(text) {
    try {
        var json = JSON.parse(text)
        return new Map(Object.entries(json))
    }
    catch {return undefined}
}

/**
 * Hash the given text using md5
 * @param {String} text
 * @returns {String} md5 hash string
 */
function md5_hash_string(text) {
    var hash = crypto.createHash("md5").update(text).digest("hex")
    return hash
}


const peers = new Peers
const wss = new Websocket.Server({port: PORT})
console.log("Websocket server listening to", PORT)

wss.on("connection", (ws) => {
    console.log("new wss connection")
    peers.add_peer(ws)
})

wss.on("error", (err) => {
    console.error("WebSocket server error:", err)
})
