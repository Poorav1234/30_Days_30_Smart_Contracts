// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ToDoList {

    struct Task {
        uint256 id;
        string description;
        bool isCompleted;
        bool isDeleted;
    }

    // Each user has their own list of tasks
    mapping(address => Task[]) private userTasks;

    // Keeps track of task IDs per user
    mapping(address => uint256) private taskCounter;

    // Events
    event TaskCreated(address indexed user, uint256 taskId, string description);
    event TaskUpdated(address indexed user, uint256 taskId, bool isCompleted);
    event TaskDeleted(address indexed user, uint256 taskId);

    // Add a new task
    function addTask(string memory _description) public {
        require(bytes(_description).length > 0, "Description is required");

        taskCounter[msg.sender]++;

        userTasks[msg.sender].push(
            Task({
                id: taskCounter[msg.sender],
                description: _description,
                isCompleted: false,
                isDeleted: false
            })
        );

        emit TaskCreated(msg.sender, taskCounter[msg.sender], _description);
    }

    // Get all tasks of the caller
    function getTasks() public view returns (Task[] memory) {
        return userTasks[msg.sender];
    }

    // Update completion status of a task
    function updateTask(uint256 _taskId, bool _isCompleted) public {
        Task[] storage tasks = userTasks[msg.sender];
        bool taskFound = false;

        for (uint256 i = 0; i < tasks.length; i++) {
            if (tasks[i].id == _taskId && !tasks[i].isDeleted) {
                tasks[i].isCompleted = _isCompleted;
                taskFound = true;
                emit TaskUpdated(msg.sender, _taskId, _isCompleted);
                break;
            }
        }

        require(taskFound, "Task not found or already deleted");
    }

    // Soft delete a task
    function deleteTask(uint256 _taskId) public {
        Task[] storage tasks = userTasks[msg.sender];
        bool taskFound = false;

        for (uint256 i = 0; i < tasks.length; i++) {
            if (tasks[i].id == _taskId && !tasks[i].isDeleted) {
                tasks[i].isDeleted = true;
                taskFound = true;
                emit TaskDeleted(msg.sender, _taskId);
                break;
            }
        }

        require(taskFound, "Task not found or already deleted");
    }
}
