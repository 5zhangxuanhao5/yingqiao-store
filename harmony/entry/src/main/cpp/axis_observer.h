#pragma once
#include <functional>
#include <string>
// Plain values copied from a UI event delivered to our own XComponent. No global
// input listener, input permission, or event pointer is retained by this module.
struct LocalAxisSample {
 int source=0,tool=0,action=0;
 bool supportedSource=false,hasHorizontal=false,hasVertical=false,hasPinch=false;
 double x=0,y=0,scale=0;
};
void SetLocalAxisRegistrationResult(int result);
void HandleLocalAxisEvent(const LocalAxisSample& sample);
void StartAxisObservation(int windowId, std::function<void(const std::string&)> forward);
void StopAxisObservation();
std::string AxisObservationStats();
bool AxisObservationIsActive();
bool AxisGestureInProgress();
