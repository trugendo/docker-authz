
from flask import Flask, jsonify, request
import base64, json
from re import search, match
import sys, os
from signal import signal, SIGUSR1

config="/etc/docker-authz/authz.json"
enabled=True
plug=Flask(__name__)
port=None
plug.debug=False

try:
    with open(config, 'r') as f:
        for key, value in json.load(f).items():
            if key=="port":
                port=value
            elif key=="debug":
                plug.debug=value
except Exception as e:
    print("error: "+str(e))
    ## don't need to kill the service

def handler(signum, sig):
    global enabled
    enabled=(False if enabled else True)

signal(SIGUSR1, handler)

@plug.route("/info/<query>", methods=["GET"])
def state(query):
    if query=="state":
        qu=(1 if enabled else 0)
        return str(qu)
    else:
        return "-1"

@plug.route("/Plugin.Activate", methods=["POST"])
def start():
    return jsonify({"Implements": ["authz"]})

@plug.route("/AuthZPlugin.AuthZReq", methods=["POST"])
def req():
    plugin_request=json.loads(request.data)
    print(plugin_request)
    response={"Allow":True}
    if search(r'/(exec)$', plugin_request["RequestUri"]) != None:
        docker_request=json.loads(base64.b64decode(plugin_request["RequestBody"]))
        if match(r'^titus$', docker_request["User"])!=None:
            response={"Allow":True}
        else:
            response={"Allow":False, "Msg":"You are not authorized to Run Execute command"}
    if not enabled:
        response={"Allow":True}
    return jsonify(**response)

@plug.route("/AuthZPlugin.AuthZRes", methods=["POST"])
def res():
    response={"Allow":True}
    return jsonify(**response)

def main():
    global port
    try:
        with open("/var/run/docker-authz.pid", 'w') as f:
            f.write(str(os.getpid()))
    except Exception as e:
        print("Error occurred while writing pid file!!")
        print(e)
    try:
        plug.run(port=(port if port!=None else 6000))
    except Exception as e:
        print("Error occcurred " + str(e))
        print("port num: " + port)

if __name__=="__main__":
    main()
