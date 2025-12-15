bind = "127.0.0.1:5000"
workers = 2
worker_class = "sync"
timeout = 120
accesslog = "/home/dietpi/logs/gunicorn_access.log"
errorlog = "/home/dietpi/logs/gunicorn_error.log"
capture_output = True
loglevel = "info"
