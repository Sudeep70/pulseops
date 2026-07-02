import time
import datetime
import socket
import requests
from flask import Flask, jsonify

app = Flask(__name__)
start_time = time.time()

def get_instance_id():
    """
    Attempts to fetch the EC2 instance ID using IMDSv2.
    Falls back to hostname if it fails (e.g. running locally).
    """
    try:
        # Step 1: Request IMDSv2 Token
        token_url = "http://169.254.169.254/latest/api/token"
        headers = {"X-aws-ec2-metadata-token-ttl-seconds": "60"}
        token_response = requests.put(token_url, headers=headers, timeout=2)
        
        if token_response.status_code == 200:
            token = token_response.text
            # Step 2: Fetch Instance ID with Token
            metadata_url = "http://169.254.169.254/latest/meta-data/instance-id"
            metadata_headers = {"X-aws-ec2-metadata-token": token}
            id_response = requests.get(metadata_url, headers=metadata_headers, timeout=2)
            if id_response.status_code == 200:
                return id_response.text
    except Exception:
        pass
    
    # Fallback to local hostname
    return f"local-host-{socket.gethostname()}"

@app.route("/")
def index():
    return jsonify({
        "message": "Welcome to PulseOps Self-Healing Pipeline Demonstration",
        "status": "online"
    })

@app.route("/health")
def health():
    uptime = int(time.time() - start_time)
    instance_id = get_instance_id()
    return jsonify({
        "status": "healthy",
        "uptime_seconds": uptime,
        "instance_id": instance_id,
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    }), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
