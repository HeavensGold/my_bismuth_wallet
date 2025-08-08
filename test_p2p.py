#!/usr/bin/env python3
import socket
import json

def send_with_header(sock, data):
    """Send data with 10-byte length header"""
    message = json.dumps(data)
    header = str(len(message)).zfill(10)
    full_message = header + message
    print(f"Sending: {full_message}")
    sock.send(full_message.encode())

def receive_with_header(sock):
    """Receive data with 10-byte length header"""
    # Read length header
    header = sock.recv(10).decode()
    print(f"Received header: '{header}'")
    
    if not header:
        return None
        
    try:
        length = int(header)
        print(f"Message length: {length}")
        
        # Read the actual message
        message = sock.recv(length).decode()
        print(f"Received message: '{message}'")
        return message
    except ValueError as e:
        print(f"Error parsing header: {e}")
        return None

def test_bismuth_p2p():
    # Connect to Bismuth peer
    peer_ip = "62.112.10.156"
    peer_port = 5658
    
    print(f"Connecting to {peer_ip}:{peer_port}")
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)  # 10 second timeout
        sock.connect((peer_ip, peer_port))
        
        print("Connected! Sending handshake...")
        
        # Send version handshake
        send_with_header(sock, "version")
        send_with_header(sock, "mainnet0022")
        
        # Try to receive response
        response = receive_with_header(sock)
        print(f"Handshake response: {response}")
        
        if response and response.strip('"') == "ok":
            print("Handshake successful! Trying balance request...")
            
            # Send balance request
            send_with_header(sock, "balancegetjson")
            send_with_header(sock, "Bis1SA7dTfbH4xhBRhgokjCvn4BG3oZ2vmkWt")
            
            # Receive balance response
            balance_response = receive_with_header(sock)
            print(f"Balance response: {balance_response}")
            
        sock.close()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_bismuth_p2p()