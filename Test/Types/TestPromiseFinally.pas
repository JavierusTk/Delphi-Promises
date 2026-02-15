unit TestPromiseFinally;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.SyncObjs, System.Classes,
  Next.Core.Promises, Next.Core.Test.Assert;

type
  [TestFixture]
  TTestPromiseFinally = class
  public
    [Test]
    /// <summary>
    /// Finally runs after resolve.
    /// </summary>
    procedure FinallyRunsAfterResolve;

    [Test]
    /// <summary>
    /// Finally runs after reject.
    /// </summary>
    procedure FinallyRunsAfterReject;

    [Test]
    /// <summary>
    /// Finally does not alter the resolved value.
    /// </summary>
    procedure FinallyDoesNotAlterResolvedValue;

    [Test]
    /// <summary>
    /// Finally does not swallow the rejection.
    /// </summary>
    procedure FinallyDoesNotSwallowRejection;

    [Test]
    /// <summary>
    /// Finally that raises replaces the original result with the new exception.
    /// </summary>
    procedure FinallyThatRaisesReplacesResult;

    [Test]
    /// <summary>
    /// Main.Finally executes in main thread.
    /// </summary>
    procedure MainFinallyExecutesInMainThread;
  end;

implementation

{ TTestPromiseFinally }

procedure TTestPromiseFinally.FinallyRunsAfterResolve;
var
  LFinallyCalled: Boolean;
  LPromise: IPromise<Integer>;
begin
  LFinallyCalled := False;
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .&Finally(procedure
    begin
      LFinallyCalled := True;
    end);

  Assert.Resolves(LPromise);
  Assert.IsTrue(LFinallyCalled);
end;

procedure TTestPromiseFinally.FinallyRunsAfterReject;
var
  LFinallyCalled: Boolean;
  LPromise: IPromise<Integer>;
begin
  LFinallyCalled := False;
  LPromise := Promise.Reject<Integer>(ETestException.Create('error'))
    .&Finally(procedure
      begin
        LFinallyCalled := True;
      end);

  Assert.Rejects(LPromise);
  Assert.IsTrue(LFinallyCalled);
end;

procedure TTestPromiseFinally.FinallyDoesNotAlterResolvedValue;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .&Finally(procedure
    begin
      // Do nothing
    end);

  Assert.Resolves(LPromise);
  Assert.AreEqual(42, LPromise.Await);
end;

procedure TTestPromiseFinally.FinallyDoesNotSwallowRejection;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Reject<Integer>(ETestException.Create('original error'))
    .&Finally(procedure
      begin
        // Do nothing
      end);

  Assert.RejectsWith(LPromise, ETestException);
end;

procedure TTestPromiseFinally.FinallyThatRaisesReplacesResult;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .&Finally(procedure
    begin
      raise ETestException.Create('finally error');
    end);

  Assert.RejectsWith(LPromise, ETestException);
end;

procedure TTestPromiseFinally.MainFinallyExecutesInMainThread;
var
  LFinallyCalled: Boolean;
  LMainThread: TThreadID;
  LPromise: IPromise<Integer>;
begin
  LMainThread := TThread.CurrentThread.ThreadID;
  LFinallyCalled := False;

  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .Main.&Finally(procedure
    begin
      LFinallyCalled := True;
      Assert.AreEqual(LMainThread, TThread.CurrentThread.ThreadID);
    end);

  Assert.Resolves(LPromise);
  Assert.IsTrue(LFinallyCalled);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPromiseFinally);

end.
