#!/bin/bash
# 使用超时时间运行 vvp
timeout 2 vvp "$@" 2>&1
