# -*- mode: snippet -*-
# name: rospy_service_server.cpp
# key: rospy, service
# --

s = rospy.Service('add_two_ints', AddTwoInts, handle_add_two_ints)

def handle_add_two_ints(req):
   return AddTwoIntsResponse(req.a + req.b)
