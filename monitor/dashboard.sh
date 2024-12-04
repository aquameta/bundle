#!/bin/bash

# Name of the tmux session (you can change it to whatever you like)
SESSION_NAME="dashboard"

# Start a new tmux session in detached mode
tmux new-session -d -s "$SESSION_NAME"

# Split the window vertically into two panes (left/right)
tmux split-window -h

# Split the top pane horizontally (top/bottom)
tmux split-window -v

# Send the command to the bottom pane
tmux send-keys -t "$SESSION_NAME:0.0" 'watch ./user_functions.sh' C-m
tmux send-keys -t "$SESSION_NAME:0.1" 'watch ./statements.sh' C-m
tmux send-keys -t "$SESSION_NAME:0.2" 'watch ./connection.sh' C-m

# Attach to the tmux session (this will bring it to the foreground)
tmux attach -t "$SESSION_NAME"
