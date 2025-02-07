pragma solidity 0.8.26;

import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {ECDSAUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {ISCServiceManager} from "./ISCServiceManager.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract SCServiceManager is  ECDSAServiceManagerBase, ISCServiceManager {
	using ECDSAUpgradeable for bytes32;

	uint32 public latestTaskNum;



	mapping(uint32 => bytes32) public allTaskHashes;

	// mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
	mapping(address => mapping(uint32 => bytes)) public allTaskResponses;

	modifier onlyOperator() {
		require(
			ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
			"Operator must be the caller"
		);
		_;
	}

	constructor(
		address _avsDirectory,
		address _stakeRegistry,
		address _delegationManager
	)
	ECDSAServiceManagerBase(
		_avsDirectory,
		_stakeRegistry,
		address(0), // hello-world doesn't need to deal with payments
		_delegationManager
	)
	{}

	/* FUNCTIONS */
	// NOTE: this function creates new task, assigns it a taskId
	function createNewTask(
		string memory name
	) external returns (Task memory) {
		// create a new task struct
		Task memory newTask;
		newTask.name = name;
		newTask.taskCreatedBlock = uint32(block.number);

		// store hash of task onchain, emit event, and increase taskNum
		allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
		emit NewTaskCreated(latestTaskNum, newTask);
		latestTaskNum = latestTaskNum + 1;

		return newTask;
	}

	function respondToTask(
		Task calldata task,
		uint32 referenceTaskIndex,
		bytes calldata signature
	) external onlyOperator {

		// TODO Temporarily disabling this until we add in staking & delegation to the Operator scripts.
		/** require(
			operatorHasMinimumWeight(msg.sender),
			string(abi.encodePacked(
			"Operator does not have match the weight requirements. ",
			"Operator weight=", 
			Strings.toString(ECDSAStakeRegistry(stakeRegistry).getLastCheckpointOperatorWeight(msg.sender)),
			", Threshold weight=", 
			Strings.toString(ECDSAStakeRegistry(stakeRegistry).getLastCheckpointThresholdWeight())
			))
			);
		 */

		// check that the task is valid, hasn't been responsed yet, and is being responded in time
		require(
			keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
			"supplied task does not match the one recorded in the contract"
		);
		require(
			allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
			"Operator has already responded to the task"
		);

		// The message that was signed
		bytes32 messageHash = keccak256(abi.encodePacked("Hello, ", task.name));
		bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

		// Recover the signer address from the signature
		address signer = ethSignedMessageHash.recover(signature);

		require(signer == msg.sender, "Message signer is not operator");

		// updating the storage with task responses
		allTaskResponses[msg.sender][referenceTaskIndex] = signature;

		// emitting event
		emit TaskResponded(referenceTaskIndex, task, msg.sender);
	}

	function operatorHasMinimumWeight(
		address operator
	) public view returns (bool) {
		return ECDSAStakeRegistry(stakeRegistry).getLastCheckpointOperatorWeight(operator)
		>= ECDSAStakeRegistry(stakeRegistry).getLastCheckpointThresholdWeight();
	}
}
