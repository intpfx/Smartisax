package com.smartisax.browser;

interface SmartisaxAgentProvider {
    String id();

    boolean needsVision();

    SmartisaxAgentAction plan(SmartisaxAgentRuntime.StepRequest request) throws Exception;
}
