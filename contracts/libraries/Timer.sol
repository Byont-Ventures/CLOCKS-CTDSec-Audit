// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v2;

library Timer {
    //=====Structs=====//
    struct Window {
        uint256 startTime;
        uint256 stopTime;
    }

    //=====Variables=====//
    // https://cryptomarketpool.com/block-timestamp-manipulation-attack/ 15 second rule
    uint256 public constant minimumWindowDuration = 20;

    //=====Events=====//
    event TransactionWindowChanged(
        uint256 oldStart,
        uint256 oldStop,
        uint256 newStart,
        uint256 newStop
    );

    //=====Functions=====//

    /// @param startTime: The amount of seconds since unix epoch till the start time
    /// @param stopTime: The amount of seconds since unix epoch till the stop time
    function setWindow(
        Window storage windowToSet,
        uint256 startTime,
        uint256 stopTime
    ) internal {
        require(stopTime > startTime, "stopTime <= startTime");
        require(
            (stopTime - startTime) >= minimumWindowDuration,
            "Window < minimumWindowDuration"
        );

        uint256 oldStartTime = windowToSet.startTime;
        uint256 oldStopTime = windowToSet.stopTime;

        windowToSet.startTime = startTime;
        windowToSet.stopTime = stopTime;

        emit TransactionWindowChanged(
            oldStartTime,
            oldStopTime,
            startTime,
            stopTime
        );
    }

    /// @notice This function checks if block.timestamp is within the given window.
    ///          The value block.timestamp can have around 15 seconds of slack since
    ///          miners can have an influence on the timestamp.
    /// @param window: The window for which block.timestamp is checked.
    function currentTimeIsInWindow(Window memory window)
        internal
        view
        returns (bool)
    {
        uint256 currentTime = block.timestamp;

        return ((currentTime >= window.startTime) &&
            (currentTime <= window.stopTime));
    }
}
