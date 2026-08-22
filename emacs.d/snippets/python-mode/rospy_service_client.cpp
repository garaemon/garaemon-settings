# -*- mode: snippet -*-
# name: rospy_service_client.cpp
# key: rospy,service
# --

service = rospy.ServiceProxy('service', Service)
service(arg1, arg2)
